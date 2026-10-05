//! Estimates an audio track's tempo (at its start and end, and its slowest/fastest) and musical key
//! (at its start and end), to seed `MediaMetadata.start_bpm`/`end_bpm`/`min_bpm`/`max_bpm`/
//! `start_key`/`end_key` on a track's first conversion (see `convert_media`).
//!
//! `ffmpeg` has no beat tracker or key detector, so it only *decodes* here (to mono f32 PCM at a low
//! sample rate -- it's already a hard requirement for audio conversion); the analysis itself is pure
//! Rust with no extra system dependencies:
//!
//! - **BPM**: log-compressed spectral flux (an onset envelope) -> autocorrelation over the plausible
//!   tempo range, with a mild prior toward ~120 BPM to tame octave errors -> a fine comb search around
//!   the winner for sub-BPM precision. Run over the first and last `BPM_WINDOW_SECONDS` of the
//!   (silence-trimmed) track for `start_bpm`/`end_bpm`, and over sliding `BPM_SLIDING_WINDOW_SECONDS`
//!   windows across the whole track for `min_bpm`/`max_bpm` (window estimates are folded into the
//!   octave of their median first, so one half/double-time misread doesn't set the min or max).
//! - **Key**: a pitch-class profile (chroma) of the first/last `BPM_WINDOW_SECONDS` of the track,
//!   correlated against the Krumhansl-Kessler major/minor key profiles.
//!
//! These are estimates -- octave errors (half/double time) and relative major/minor mix-ups are the
//! usual failure modes -- which is why they only fill *unset* fields and stay owner-editable.

use std::f32::consts::PI;
use std::path::Path;
use std::process::Command;

use anyhow::{bail, Context, Result};

use crate::models::MediaMetadata;

/// Sample rate the analysis runs at. Plenty for tempo (onsets are broadband) and for chroma
/// (fundamentals/low harmonics below ~5kHz), and keeps a long track's PCM small.
pub const ANALYSIS_SAMPLE_RATE: u32 = 11_025;
/// Longest stretch of a track that's decoded for analysis (~40MB of f32 PCM at most).
const MAX_ANALYSIS_SECONDS: usize = 15 * 60;
/// How much of the start/end of a track each BPM estimate looks at.
const BPM_WINDOW_SECONDS: usize = 30;
/// Window length/hop for the sliding tempo scan behind `min_bpm`/`max_bpm`.
const BPM_SLIDING_WINDOW_SECONDS: usize = 20;
const BPM_SLIDING_HOP_SECONDS: usize = 10;
/// Shortest stretch a key is estimated from.
const MIN_KEY_SECONDS: usize = 6;
/// A tempo estimate whose pulse (normalized onset autocorrelation) is weaker than this is noise.
const MIN_PULSE_STRENGTH: f32 = 0.4;
/// Shortest stretch BPM is estimated from; below this the autocorrelation has too few beats.
const MIN_BPM_SECONDS: usize = 6;
const BPM_RANGE: (f32, f32) = (60.0, 200.0);

// Onset envelope STFT.
const FLUX_FRAME: usize = 1024;
const FLUX_HOP: usize = 128;
// Chroma STFT -- longer frames, since low notes need fine frequency resolution.
const CHROMA_FRAME: usize = 8192;
const CHROMA_HOP: usize = 4096;
const CHROMA_FREQ_RANGE: (f32, f32) = (65.0, 2100.0);

/// What `analyze_audio` could confidently work out; `None` for anything it couldn't.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct AudioAnalysis {
    pub start_bpm: Option<f32>,
    pub end_bpm: Option<f32>,
    pub min_bpm: Option<f32>,
    pub max_bpm: Option<f32>,
    pub start_key: Option<String>,
    pub end_key: Option<String>,
}

impl AudioAnalysis {
    /// As a `MediaMetadata` with only the musical fields set, ready for `fill_missing_credits`.
    pub fn into_metadata(self) -> MediaMetadata {
        MediaMetadata {
            start_bpm: self.start_bpm,
            end_bpm: self.end_bpm,
            min_bpm: self.min_bpm,
            max_bpm: self.max_bpm,
            start_key: self.start_key,
            end_key: self.end_key,
            ..Default::default()
        }
    }
}

/// Decodes `path` (any audio/video file `ffmpeg` can read) to mono PCM at `ANALYSIS_SAMPLE_RATE`.
pub fn decode_mono_pcm(path: &Path) -> Result<Vec<f32>> {
    let output = Command::new("ffmpeg")
        .args(["-nostdin", "-v", "error", "-i"])
        .arg(path)
        .args(["-vn", "-t"])
        .arg(MAX_ANALYSIS_SECONDS.to_string())
        .args(["-ac", "1", "-ar"])
        .arg(ANALYSIS_SAMPLE_RATE.to_string())
        .args(["-f", "f32le", "pipe:1"])
        .output()
        .context("failed to run ffmpeg")?;
    if !output.status.success() {
        bail!(
            "ffmpeg exited with {}: {}",
            output.status,
            String::from_utf8_lossy(&output.stderr)
        );
    }
    Ok(output
        .stdout
        .chunks_exact(4)
        .map(|b| f32::from_le_bytes([b[0], b[1], b[2], b[3]]))
        .collect())
}

/// Decodes and analyzes the audio file at `path`.
pub fn analyze_audio_file(path: &Path) -> Result<AudioAnalysis> {
    Ok(analyze_audio(&decode_mono_pcm(path)?))
}

/// Analyzes mono PCM at `ANALYSIS_SAMPLE_RATE`. Pure, so it's testable on synthesized audio.
pub fn analyze_audio(samples: &[f32]) -> AudioAnalysis {
    let sr = ANALYSIS_SAMPLE_RATE as usize;
    let trimmed = trim_silence(samples);

    // Keys: first/last 30s, or the whole thing (for both) when the track is too short to split.
    let key_window = (BPM_WINDOW_SECONDS * sr).min(trimmed.len() / 2);
    let (start_key, end_key) = if key_window >= MIN_KEY_SECONDS * sr {
        (estimate_key(&trimmed[..key_window]), estimate_key(&trimmed[trimmed.len() - key_window..]))
    } else {
        let whole = if trimmed.len() >= MIN_KEY_SECONDS * sr { estimate_key(trimmed) } else { None };
        (whole.clone(), whole)
    };

    // Tempos, all from one onset envelope of the whole track.
    let flux = onset_envelope(trimmed);
    let fps = flux_frames_per_second();
    let frames = |seconds: usize| (seconds as f32 * fps) as usize;
    let end_window = frames(BPM_WINDOW_SECONDS).min(flux.len() / 2);
    let (start_bpm, end_bpm) = if end_window >= frames(MIN_BPM_SECONDS) {
        (
            estimate_bpm_from_flux(&flux[..end_window]),
            estimate_bpm_from_flux(&flux[flux.len() - end_window..]),
        )
    } else {
        // Too short to compare the two ends: one estimate over the whole thing serves as both.
        let whole = estimate_bpm_from_flux(&flux);
        (whole, whole)
    };

    let (window, hop) = (frames(BPM_SLIDING_WINDOW_SECONDS), frames(BPM_SLIDING_HOP_SECONDS));
    let mut window_bpms: Vec<f32> = Vec::new();
    if flux.len() >= window {
        let mut at = 0;
        while at + window <= flux.len() {
            window_bpms.extend(estimate_bpm_from_flux(&flux[at..at + window]));
            at += hop;
        }
        // The last window, aligned to the end of the track.
        window_bpms.extend(estimate_bpm_from_flux(&flux[flux.len() - window..]));
    }
    let mut all: Vec<f32> = window_bpms.iter().cloned().chain(start_bpm).chain(end_bpm).collect();
    all.sort_by(|a, b| a.total_cmp(b));
    let Some(&median) = all.get(all.len() / 2) else {
        return AudioAnalysis { start_key, end_key, ..Default::default() };
    };
    let fold = |bpm: f32| fold_octave(bpm, median);
    let (start_bpm, end_bpm) = (start_bpm.map(fold), end_bpm.map(fold));
    // The extremes ignore the very slowest/fastest 10% of windows, so one confused window (a
    // transition between tempos, say) doesn't define the track -- but never exclude the ends.
    let mut folded: Vec<f32> = all.into_iter().map(fold).collect();
    folded.sort_by(|a, b| a.total_cmp(b));
    let trim = (folded.len() - 1) / 10;
    let (mut min_bpm, mut max_bpm) = (folded[trim], folded[folded.len() - 1 - trim]);
    for bpm in start_bpm.into_iter().chain(end_bpm) {
        min_bpm = min_bpm.min(bpm);
        max_bpm = max_bpm.max(bpm);
    }
    let round = |bpm: f32| (bpm * 10.0).round() / 10.0;
    AudioAnalysis {
        start_bpm: start_bpm.map(round),
        end_bpm: end_bpm.map(round),
        min_bpm: Some(round(min_bpm)),
        max_bpm: Some(round(max_bpm)),
        start_key,
        end_key,
    }
}

/// `bpm`, or half/double of it if that lands within 4% of `reference` -- a window that locked on
/// the half- or double-time pulse of the same groove.
fn fold_octave(bpm: f32, reference: f32) -> f32 {
    [bpm * 0.5, bpm * 2.0]
        .into_iter()
        .find(|candidate| (candidate / reference - 1.0).abs() < 0.04)
        .unwrap_or(bpm)
}

/// Drops leading/trailing near-silence (below about -50 dBFS RMS), where there's nothing to analyze.
fn trim_silence(samples: &[f32]) -> &[f32] {
    const BLOCK: usize = 2048;
    const THRESHOLD: f32 = 0.003;
    let loud = |block: &[f32]| (block.iter().map(|s| s * s).sum::<f32>() / block.len() as f32).sqrt() > THRESHOLD;
    let first = samples.chunks(BLOCK).position(loud);
    let last = samples.chunks(BLOCK).rposition(loud);
    match (first, last) {
        (Some(first), Some(last)) => &samples[first * BLOCK..((last + 1) * BLOCK).min(samples.len())],
        _ => &[],
    }
}

// ---------------------------------------------------------------------------------------------------
// FFT
// ---------------------------------------------------------------------------------------------------

/// In-place iterative radix-2 FFT; `re.len()` (== `im.len()`) must be a power of two.
fn fft(re: &mut [f32], im: &mut [f32]) {
    let n = re.len();
    debug_assert!(n.is_power_of_two() && im.len() == n);
    let mut j = 0;
    for i in 1..n {
        let mut bit = n >> 1;
        while j & bit != 0 {
            j ^= bit;
            bit >>= 1;
        }
        j ^= bit;
        if i < j {
            re.swap(i, j);
            im.swap(i, j);
        }
    }
    let mut len = 2;
    while len <= n {
        let angle = -2.0 * PI / len as f32;
        let (w_im, w_re) = angle.sin_cos();
        for start in (0..n).step_by(len) {
            let (mut cur_re, mut cur_im) = (1.0f32, 0.0f32);
            for k in 0..len / 2 {
                let (a, b) = (start + k, start + k + len / 2);
                let t_re = re[b] * cur_re - im[b] * cur_im;
                let t_im = re[b] * cur_im + im[b] * cur_re;
                re[b] = re[a] - t_re;
                im[b] = im[a] - t_im;
                re[a] += t_re;
                im[a] += t_im;
                let next_re = cur_re * w_re - cur_im * w_im;
                cur_im = cur_re * w_im + cur_im * w_re;
                cur_re = next_re;
            }
        }
        len <<= 1;
    }
}

fn hann(n: usize) -> Vec<f32> {
    (0..n).map(|i| 0.5 - 0.5 * (2.0 * PI * i as f32 / n as f32).cos()).collect()
}

/// Magnitude spectrum (bins `0..frame/2`) of each Hann-windowed `frame`-sample frame of `samples`,
/// advancing `hop` samples at a time.
fn magnitude_frames(samples: &[f32], frame: usize, hop: usize) -> Vec<Vec<f32>> {
    if samples.len() < frame {
        return Vec::new();
    }
    let window = hann(frame);
    let (mut re, mut im) = (vec![0.0f32; frame], vec![0.0f32; frame]);
    (0..=(samples.len() - frame) / hop)
        .map(|i| {
            let chunk = &samples[i * hop..i * hop + frame];
            for ((r, s), w) in re.iter_mut().zip(chunk).zip(&window) {
                *r = s * w;
            }
            im.fill(0.0);
            fft(&mut re, &mut im);
            (0..frame / 2).map(|k| (re[k] * re[k] + im[k] * im[k]).sqrt()).collect()
        })
        .collect()
}

// ---------------------------------------------------------------------------------------------------
// BPM
// ---------------------------------------------------------------------------------------------------

fn flux_frames_per_second() -> f32 {
    ANALYSIS_SAMPLE_RATE as f32 / FLUX_HOP as f32
}

/// The tempo of `samples` in BPM, if there's a clear enough pulse.
#[cfg(test)]
fn estimate_bpm(samples: &[f32]) -> Option<f32> {
    estimate_bpm_from_flux(&onset_envelope(samples))
}

/// The tempo (in BPM, to 0.1) of a stretch of onset envelope (see `onset_envelope`), if there's a
/// clear enough pulse.
fn estimate_bpm_from_flux(flux: &[f32]) -> Option<f32> {
    let fps = flux_frames_per_second();
    if flux.len() < (MIN_BPM_SECONDS as f32 * fps) as usize {
        return None;
    }
    let acf = autocorrelation(flux, (fps * 60.0 / BPM_RANGE.0 * 2.0).ceil() as usize + 2);
    if acf[0] <= f32::EPSILON {
        return None; // dead flat: no onsets at all
    }
    let at = |lag: f32| interpolate(&acf, lag) / acf[0];

    // Coarse: best-scoring tempo on a 0.25 BPM grid. A pulse at lag L also shows up at 2L and (for
    // subdivisions) L/2, so those support the candidate; the prior prefers tempi nearer 120.
    let mut best: Option<(f32, f32)> = None; // (score, bpm)
    let mut bpm = BPM_RANGE.0;
    while bpm <= BPM_RANGE.1 {
        let lag = fps * 60.0 / bpm;
        let prior = (-0.5 * (bpm / 120.0).log2().powi(2) / 1.2f32.powi(2)).exp();
        let score = (at(lag) + 0.5 * at(2.0 * lag) + 0.25 * at(lag / 2.0)) * prior;
        if best.is_none_or(|(s, _)| score > s) {
            best = Some((score, bpm));
        }
        bpm += 0.25;
    }
    let (_, coarse_bpm) = best?;
    // Not a pulse, just noise: the autocorrelation at the winning period is barely above chance.
    if at(fps * 60.0 / coarse_bpm) < MIN_PULSE_STRENGTH {
        return None;
    }
    Some(refine_bpm(flux, fps, coarse_bpm))
}

/// Half-wave-rectified, log-compressed spectral flux per hop, minus its local mean (so only onsets
/// that stand out from the surrounding texture remain).
fn onset_envelope(samples: &[f32]) -> Vec<f32> {
    let spectra: Vec<Vec<f32>> = magnitude_frames(samples, FLUX_FRAME, FLUX_HOP)
        .into_iter()
        .map(|frame| frame.into_iter().map(|m| (1.0 + 10.0 * m).ln()).collect())
        .collect();
    let flux: Vec<f32> = std::iter::once(0.0)
        .chain(spectra.windows(2).map(|pair| {
            pair[0].iter().zip(&pair[1]).map(|(a, b)| (b - a).max(0.0)).sum::<f32>()
        }))
        .collect();

    // Local mean over ~0.5s via a running sum.
    let half = (ANALYSIS_SAMPLE_RATE as usize / FLUX_HOP) / 4;
    let mut prefix = vec![0.0f32; flux.len() + 1];
    for (i, f) in flux.iter().enumerate() {
        prefix[i + 1] = prefix[i] + f;
    }
    (0..flux.len())
        .map(|i| {
            let (lo, hi) = (i.saturating_sub(half), (i + half + 1).min(flux.len()));
            (flux[i] - (prefix[hi] - prefix[lo]) / (hi - lo) as f32).max(0.0)
        })
        .collect()
}

/// Unbiased autocorrelation of `signal` for lags `0..max_lag`.
fn autocorrelation(signal: &[f32], max_lag: usize) -> Vec<f32> {
    (0..max_lag.min(signal.len()))
        .map(|lag| {
            let sum: f32 = signal.iter().zip(&signal[lag..]).map(|(a, b)| a * b).sum();
            sum / (signal.len() - lag) as f32
        })
        .collect()
}

/// `values[x]` linearly interpolated at fractional `x` (0 beyond the end).
fn interpolate(values: &[f32], x: f32) -> f32 {
    let i = x.floor() as usize;
    match (values.get(i), values.get(i + 1)) {
        (Some(a), Some(b)) => a + (b - a) * x.fract(),
        (Some(a), None) => *a,
        _ => 0.0,
    }
}

/// Sharpens `coarse_bpm` (good to a couple of percent) by sliding a pulse train over the onset
/// envelope: the period (and phase) whose pulses collect the most onset energy over the whole window
/// wins -- tiny period errors add up across dozens of beats, so this resolves far finer than one
/// frame of autocorrelation lag.
fn refine_bpm(flux: &[f32], fps: f32, coarse_bpm: f32) -> f32 {
    let coarse_period = fps * 60.0 / coarse_bpm;
    let mut best = (f32::MIN, coarse_bpm);
    let mut period = coarse_period * 0.97;
    while period <= coarse_period * 1.03 {
        let mut phase = 0.0;
        while phase < period {
            let mut score = 0.0;
            let mut pos = phase;
            while pos < (flux.len() - 1) as f32 {
                score += interpolate(flux, pos);
                pos += period;
            }
            if score > best.0 {
                best = (score, fps * 60.0 / period);
            }
            phase += 0.5;
        }
        period += coarse_period * 0.0004;
    }
    best.1
}

// ---------------------------------------------------------------------------------------------------
// Key
// ---------------------------------------------------------------------------------------------------

/// Krumhansl-Kessler key profiles, indexed by pitch class relative to the tonic.
const MAJOR_PROFILE: [f32; 12] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88];
const MINOR_PROFILE: [f32; 12] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17];
/// Tonic names by pitch class from C. Majors are bare (`F`), minors `m`-suffixed (`Am`); the usual
/// enharmonic spelling (flats for most, `F#`/`C#m`/`G#m`/`F#m`) is used.
const MAJOR_NAMES: [&str; 12] = ["C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"];
const MINOR_NAMES: [&str; 12] = ["Cm", "C#m", "Dm", "Ebm", "Em", "Fm", "F#m", "Gm", "G#m", "Am", "Bbm", "Bm"];

/// The most likely key of `samples`, if they're tonal enough to say.
fn estimate_key(samples: &[f32]) -> Option<String> {
    let chroma = chromagram(samples)?;
    let mut best: Option<(f32, String)> = None;
    for tonic in 0..12 {
        for (profile, names) in [(&MAJOR_PROFILE, &MAJOR_NAMES), (&MINOR_PROFILE, &MINOR_NAMES)] {
            let rotated: Vec<f32> = (0..12).map(|pc| profile[(pc + 12 - tonic) % 12]).collect();
            let corr = pearson(&chroma, &rotated);
            if best.as_ref().is_none_or(|(c, _)| corr > *c) {
                best = Some((corr, names[tonic].to_string()));
            }
        }
    }
    // Atonal/noisy material correlates with every key about equally badly.
    best.filter(|(corr, _)| *corr >= 0.45).map(|(_, key)| key)
}

/// Total spectral-peak energy per pitch class (index 0 = C) across the whole of `samples`.
fn chromagram(samples: &[f32]) -> Option<[f32; 12]> {
    let bin_hz = ANALYSIS_SAMPLE_RATE as f32 / CHROMA_FRAME as f32;
    let mut chroma = [0.0f32; 12];
    for frame in magnitude_frames(samples, CHROMA_FRAME, CHROMA_HOP) {
        // Per-frame normalization so a loud passage doesn't drown out the rest of the track.
        let frame_peak = frame.iter().cloned().fold(0.0f32, f32::max);
        if frame_peak <= f32::EPSILON {
            continue;
        }
        for k in 1..frame.len() - 1 {
            let hz = k as f32 * bin_hz;
            if hz < CHROMA_FREQ_RANGE.0 || hz > CHROMA_FREQ_RANGE.1 {
                continue;
            }
            // Spectral peaks only: the skirt around a partial isn't extra pitch information.
            if frame[k] < frame[k - 1] || frame[k] <= frame[k + 1] {
                continue;
            }
            let midi = 69.0 + 12.0 * (hz / 440.0).log2();
            chroma[(midi.round() as i32).rem_euclid(12) as usize] += (frame[k] / frame_peak).sqrt();
        }
    }
    (chroma.iter().sum::<f32>() > f32::EPSILON).then_some(chroma)
}

fn pearson(a: &[f32], b: &[f32]) -> f32 {
    let (mean_a, mean_b) = (a.iter().sum::<f32>() / a.len() as f32, b.iter().sum::<f32>() / b.len() as f32);
    let (mut cov, mut var_a, mut var_b) = (0.0, 0.0, 0.0);
    for (x, y) in a.iter().zip(b) {
        cov += (x - mean_a) * (y - mean_b);
        var_a += (x - mean_a).powi(2);
        var_b += (y - mean_b).powi(2);
    }
    if var_a <= f32::EPSILON || var_b <= f32::EPSILON {
        return 0.0;
    }
    cov / (var_a * var_b).sqrt()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::is_valid_musical_key;

    const SR: f32 = ANALYSIS_SAMPLE_RATE as f32;

    /// A drum-ish click track: a decaying noise burst on every beat, silence between.
    fn click_track(bpm: f32, seconds: f32) -> Vec<f32> {
        let mut samples = vec![0.0f32; (seconds * SR) as usize];
        let beat_samples = SR * 60.0 / bpm;
        let mut seed = 12345u32;
        let mut beat = 0.0;
        while (beat as usize) < samples.len() {
            for i in 0..(0.05 * SR) as usize {
                let idx = beat as usize + i;
                if idx >= samples.len() {
                    break;
                }
                seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
                let noise = (seed >> 8) as f32 / (1u32 << 24) as f32 * 2.0 - 1.0;
                samples[idx] += noise * (-(i as f32) / (0.01 * SR)).exp() * 0.8;
            }
            beat += beat_samples;
        }
        samples
    }

    /// Sustained chords (each `chord_seconds` long) of 4-harmonic tones. `chords` are lists of MIDI notes.
    fn chord_progression(chords: &[&[u32]], chord_seconds: f32, repeats: usize) -> Vec<f32> {
        let mut samples = Vec::new();
        for _ in 0..repeats {
            for chord in chords {
                for i in 0..(chord_seconds * SR) as usize {
                    let t = i as f32 / SR;
                    samples.push(
                        chord
                            .iter()
                            .map(|note| {
                                let f = 440.0 * 2.0f32.powf((*note as f32 - 69.0) / 12.0);
                                (1..=4).map(|h| (2.0 * PI * f * h as f32 * t).sin() / h as f32).sum::<f32>()
                            })
                            .sum::<f32>()
                            * 0.1,
                    );
                }
            }
        }
        samples
    }

    #[test]
    fn fft_finds_a_sine() {
        let n = 1024;
        let mut re: Vec<f32> = (0..n).map(|i| (2.0 * PI * 64.0 * i as f32 / n as f32).sin()).collect();
        let mut im = vec![0.0; n];
        fft(&mut re, &mut im);
        let mags: Vec<f32> = (0..n / 2).map(|k| (re[k] * re[k] + im[k] * im[k]).sqrt()).collect();
        let peak = mags.iter().cloned().enumerate().fold((0, 0.0), |a, b| if b.1 > a.1 { b } else { a });
        assert_eq!(peak.0, 64);
        assert!((peak.1 - n as f32 / 2.0).abs() < 1.0);
    }

    #[test]
    fn detects_click_track_tempos() {
        for bpm in [78.0, 100.0, 128.0, 140.0] {
            let detected = estimate_bpm(&click_track(bpm, 30.0)).unwrap_or_else(|| panic!("no tempo found for {bpm}"));
            assert!((detected - bpm).abs() < 1.0, "expected ~{bpm}, got {detected}");
        }
    }

    /// Equal-strength pulses are ambiguous between a tempo and its half; either is an acceptable read.
    #[test]
    fn fast_click_track_may_read_as_half_time() {
        let detected = estimate_bpm(&click_track(174.0, 30.0)).unwrap();
        assert!((detected - 174.0).abs() < 1.5 || (detected - 87.0).abs() < 1.0, "got {detected}");
    }

    #[test]
    fn tempo_range_and_ends_across_a_tempo_change() {
        let mut samples = click_track(100.0, 40.0);
        samples.extend(click_track(140.0, 40.0));
        let analysis = analyze_audio(&samples);
        assert!((analysis.start_bpm.unwrap() - 100.0).abs() < 1.0, "{analysis:?}");
        assert!((analysis.end_bpm.unwrap() - 140.0).abs() < 1.0, "{analysis:?}");
        assert!((analysis.min_bpm.unwrap() - 100.0).abs() < 1.0, "{analysis:?}");
        assert!((analysis.max_bpm.unwrap() - 140.0).abs() < 1.0, "{analysis:?}");
    }

    #[test]
    fn steady_track_has_equal_start_end_min_max() {
        let analysis = analyze_audio(&click_track(120.0, 60.0));
        for bpm in [analysis.start_bpm, analysis.end_bpm, analysis.min_bpm, analysis.max_bpm] {
            assert!((bpm.unwrap() - 120.0).abs() < 1.0, "{analysis:?}");
        }
    }

    #[test]
    fn octave_misreads_dont_set_min_or_max() {
        assert_eq!(fold_octave(60.0, 121.0), 120.0);
        assert_eq!(fold_octave(242.0, 120.0), 121.0);
        assert_eq!(fold_octave(100.0, 140.0), 100.0, "a genuinely different tempo stays");
    }

    #[test]
    fn silence_and_noise_have_no_tempo_or_key() {
        assert_eq!(analyze_audio(&vec![0.0; 40 * SR as usize]), AudioAnalysis::default());
        let mut seed = 99u32;
        let noise: Vec<f32> = (0..40 * SR as usize)
            .map(|_| {
                seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
                ((seed >> 8) as f32 / (1u32 << 24) as f32 * 2.0 - 1.0) * 0.3
            })
            .collect();
        assert_eq!(analyze_audio(&noise), AudioAnalysis::default());
    }

    #[test]
    fn too_short_for_tempo_is_none() {
        assert_eq!(analyze_audio(&click_track(120.0, 3.0)).start_bpm, None);
    }

    #[test]
    fn detects_major_and_minor_keys() {
        // C - F - G - C
        let c_major = chord_progression(&[&[48, 55, 60, 64], &[53, 57, 60, 65], &[55, 59, 62, 67], &[48, 55, 60, 64]], 2.0, 4);
        assert_eq!(estimate_key(&c_major).as_deref(), Some("C"));
        // Am - Dm - E - Am
        let a_minor = chord_progression(&[&[45, 57, 60, 64], &[50, 57, 62, 65], &[52, 56, 59, 64], &[45, 57, 60, 64]], 2.0, 4);
        assert_eq!(estimate_key(&a_minor).as_deref(), Some("Am"));
        // Transposed up 3 semitones: Eb - Ab - Bb - Eb
        let e_flat = chord_progression(&[&[51, 58, 63, 67], &[56, 60, 63, 68], &[58, 62, 65, 70], &[51, 58, 63, 67]], 2.0, 4);
        assert_eq!(estimate_key(&e_flat).as_deref(), Some("Eb"));
    }

    #[test]
    fn start_and_end_keys_are_independent() {
        let c_major = chord_progression(&[&[48, 55, 60, 64], &[53, 57, 60, 65], &[55, 59, 62, 67], &[48, 55, 60, 64]], 2.0, 4);
        let a_minor = chord_progression(&[&[45, 57, 60, 64], &[50, 57, 62, 65], &[52, 56, 59, 64], &[45, 57, 60, 64]], 2.0, 4);
        let analysis = analyze_audio(&[c_major, a_minor].concat());
        assert_eq!(analysis.start_key.as_deref(), Some("C"));
        assert_eq!(analysis.end_key.as_deref(), Some("Am"));
    }

    #[test]
    fn every_detectable_key_name_is_a_valid_key() {
        for name in MAJOR_NAMES.iter().chain(&MINOR_NAMES) {
            assert!(is_valid_musical_key(name), "{name}");
        }
    }

    /// End to end against the real `ffmpeg`, skipped where it isn't installed.
    #[test]
    fn analyzes_a_real_encoded_file() {
        if Command::new("ffmpeg").arg("-version").output().is_err() {
            return;
        }
        let dir = std::env::temp_dir().join(format!("audio-analysis-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("tone.mp3");
        // ffmpeg's own metronome-ish source: a 440Hz beep, 2 per second (120 BPM).
        let status = Command::new("ffmpeg")
            .args(["-y", "-nostdin", "-v", "error", "-f", "lavfi", "-i"])
            .arg("aevalsrc='sin(2*PI*440*t)*lt(mod(t,0.5),0.05)':s=44100:d=30")
            .arg(&path)
            .status()
            .unwrap();
        assert!(status.success());
        let analysis = analyze_audio_file(&path).unwrap();
        let _ = std::fs::remove_dir_all(&dir);
        assert!((analysis.start_bpm.unwrap() - 120.0).abs() < 1.5, "{analysis:?}");
        assert!((analysis.end_bpm.unwrap() - 120.0).abs() < 1.5, "{analysis:?}");
    }
}
