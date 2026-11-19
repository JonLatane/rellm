//! Where a search's time goes. A search is several steps that can each be the slow one -- the Postgres full-text
//! query, embedding the query (a call to the embedding service), then either the vector search service or the Postgres
//! scan (candidate ids, loading their vectors into this process, scoring them), the visibility check, and the final
//! page load -- so each step reports its time here and the search logs ONE line with all of them, at `info`:
//!
//! ```text
//! Search timings (post): 1043ms in all = Postgres full-text 34ms + server configuration 3ms + embed the query 812ms
//! (3ms of it waiting for this server's embedder) + vector search service 22ms + Postgres visibility check 9ms +
//! Postgres page load 15ms; 148ms elsewhere.
//! ```
//!
//! A handler starts a `SearchTimer` for the search; the steps call `timed`/`record` from wherever they run. The timer is
//! per thread (a search is synchronous: it must stay on one thread, so never hold a `SearchTimer` across an `.await`),
//! which keeps the semantic-search functions' signatures as they are, and everything is a no-op outside a search
//! (the jobs, tests). Durations and counts only: never the query text.

use std::cell::RefCell;
use std::time::{Duration, Instant};

use super::EmbeddingKind;

/// One step of a search.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Stage {
    /// The Postgres full-text query (matching ids, then ranking them).
    FullText,
    /// Reading the active server configuration (a small Postgres query, done at the start of each semantic step).
    Configuration,
    /// Embedding the search query: waiting for this server's embedder, and the call to the embedding service.
    Embed,
    /// The vector search service: the round trip for the nearest ids anywhere.
    VectorService,
    /// Postgres: which of the vector search service's ids this viewer may see.
    Visibility,
    /// Postgres scan only: the ids of the candidate rows (the newest visible ones plus the full-text matches).
    Candidates,
    /// Postgres scan only: reading the candidates' vectors out of Postgres and into this process.
    VectorLoad,
    /// Postgres scan only: scoring the loaded vectors against the query here.
    Similarity,
    /// Loading the rows of the page that is returned.
    PageLoad,
}

impl Stage {
    fn label(self) -> &'static str {
        match self {
            Stage::FullText => "Postgres full-text",
            Stage::Configuration => "server configuration",
            Stage::Embed => "embed the query",
            Stage::VectorService => "vector search service",
            Stage::Visibility => "Postgres visibility check",
            Stage::Candidates => "Postgres candidate ids",
            Stage::VectorLoad => "Postgres vector load",
            Stage::Similarity => "similarity scoring",
            Stage::PageLoad => "Postgres page load",
        }
    }

    /// Part of semantic search (as opposed to the full-text search and the page load every search has).
    fn is_semantic(self) -> bool {
        !matches!(self, Stage::FullText | Stage::PageLoad)
    }
}

struct Collector {
    kind: EmbeddingKind,
    started: Instant,
    /// In the order first recorded; a step run twice (an event search asks Postgres for ids twice) adds up.
    stages: Vec<(Stage, Duration, Option<String>)>,
}

thread_local! {
    static ACTIVE: RefCell<Option<Collector>> = const { RefCell::new(None) };
}

/// A search being timed; logs its summary line when dropped (when it did any semantic work: a plain full-text search
/// -- semantic search off, or nothing to rank -- is not worth a line).
pub struct SearchTimer {
    /// A timer that was already running on this thread (none, unless searches nest), restored afterwards.
    outer: Option<Collector>,
}

pub fn begin(kind: EmbeddingKind) -> SearchTimer {
    let outer = ACTIVE.with(|active| active.borrow_mut().replace(Collector { kind, started: Instant::now(), stages: Vec::new() }));
    SearchTimer { outer }
}

impl Drop for SearchTimer {
    fn drop(&mut self) {
        let finished = ACTIVE.with(|active| std::mem::replace(&mut *active.borrow_mut(), self.outer.take()));
        if let Some(collector) = finished {
            if collector.stages.iter().any(|(stage, _, _)| stage.is_semantic()) {
                log::info!("{}", summary(&collector, collector.started.elapsed()));
            }
        }
    }
}

/// Adds `elapsed` to `stage` of the search running on this thread, if any.
pub fn record_duration(stage: Stage, elapsed: Duration) {
    add(stage, elapsed, None);
}

/// `record_duration` for the time since `since`.
pub fn record(stage: Stage, since: Instant) {
    add(stage, since.elapsed(), None);
}

/// `record`, with a note shown beside the step (a count of vectors, time spent waiting).
pub fn record_with(stage: Stage, since: Instant, note: String) {
    add(stage, since.elapsed(), Some(note));
}

/// Runs `work` and records how long it took as `stage`.
pub fn timed<T>(stage: Stage, work: impl FnOnce() -> T) -> T {
    let started = Instant::now();
    let result = work();
    record(stage, started);
    result
}

/// The steps recorded so far by the search running on this thread, with their notes.
#[cfg(test)]
pub fn recorded() -> Vec<(Stage, Option<String>)> {
    ACTIVE.with(|active| active.borrow().as_ref().map(|c| c.stages.iter().map(|(s, _, n)| (*s, n.clone())).collect()).unwrap_or_default())
}

fn add(stage: Stage, elapsed: Duration, note: Option<String>) {
    ACTIVE.with(|active| {
        if let Some(collector) = active.borrow_mut().as_mut() {
            match collector.stages.iter_mut().find(|(s, _, _)| *s == stage) {
                Some((_, total, existing)) => {
                    *total += elapsed;
                    // A repeated step keeps its latest note.
                    if note.is_some() {
                        *existing = note;
                    }
                }
                None => collector.stages.push((stage, elapsed, note)),
            }
        }
    });
}

fn summary(collector: &Collector, total: Duration) -> String {
    let accounted: Duration = collector.stages.iter().map(|(_, d, _)| *d).sum();
    let steps: Vec<String> = collector
        .stages
        .iter()
        .map(|(stage, d, note)| match note {
            Some(note) => format!("{} {}ms ({})", stage.label(), d.as_millis(), note),
            None => format!("{} {}ms", stage.label(), d.as_millis()),
        })
        .collect();
    format!(
        "Search timings ({}): {}ms in all = {}; {}ms elsewhere.",
        collector.kind.name(),
        total.as_millis(),
        steps.join(" + "),
        total.saturating_sub(accounted).as_millis()
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn collected(f: impl FnOnce()) -> Vec<(Stage, Duration)> {
        let timer = begin(EmbeddingKind::Post);
        f();
        let stages = ACTIVE.with(|a| a.borrow().as_ref().unwrap().stages.iter().map(|(s, d, _)| (*s, *d)).collect());
        drop(timer);
        stages
    }

    #[test]
    fn steps_run_twice_add_up_and_keep_their_first_position() {
        let stages = collected(|| {
            record_duration(Stage::FullText, Duration::from_millis(10));
            record_duration(Stage::Candidates, Duration::from_millis(5));
            record_duration(Stage::Candidates, Duration::from_millis(7));
        });
        assert_eq!(stages, vec![(Stage::FullText, Duration::from_millis(10)), (Stage::Candidates, Duration::from_millis(12))]);
    }

    #[test]
    fn recording_outside_a_search_does_nothing() {
        record_duration(Stage::Embed, Duration::from_secs(1));
        assert!(ACTIVE.with(|a| a.borrow().is_none()));
        assert_eq!(timed(Stage::Embed, || 7), 7);
    }

    #[test]
    fn a_timer_leaves_nothing_behind_and_restores_an_outer_one() {
        let outer = begin(EmbeddingKind::Post);
        record_duration(Stage::FullText, Duration::from_millis(1));
        {
            let _inner = begin(EmbeddingKind::Event);
            record_duration(Stage::Embed, Duration::from_millis(2));
        }
        let stages = ACTIVE.with(|a| a.borrow().as_ref().unwrap().stages.iter().map(|(s, _, _)| *s).collect::<Vec<_>>());
        assert_eq!(stages, vec![Stage::FullText], "the inner search's steps stay out of the outer one's");
        drop(outer);
        assert!(ACTIVE.with(|a| a.borrow().is_none()));
    }

    #[test]
    fn the_summary_names_every_step_and_what_is_left_over() {
        let timer = Collector {
            kind: EmbeddingKind::Event,
            started: Instant::now(),
            stages: vec![
                (Stage::FullText, Duration::from_millis(30), None),
                (Stage::VectorLoad, Duration::from_millis(40), Some("9812 vectors, 14.4MB".to_string())),
            ],
        };
        let line = summary(&timer, Duration::from_millis(100));
        assert_eq!(
            line,
            "Search timings (event): 100ms in all = Postgres full-text 30ms + Postgres vector load 40ms (9812 vectors, 14.4MB); 30ms elsewhere."
        );
    }
}
