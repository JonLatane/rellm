use std::path::Path;
use std::str::FromStr;

use super::{load_media_file_data, load_media_file_data_preferring, open_named_file, RocketState};
use crate::{
    logic::ImageMagick,
    protos::{MediaConversion, ServerInfo, ServerLogo},
    rpcs::{get_server_configuration_proto, get_service_version},
};
use base64::{prelude::BASE64_STANDARD, Engine};
use percent_encoding::{utf8_percent_encode, AsciiSet, NON_ALPHANUMERIC};
use rocket::{
    fs::NamedFile,
    http::{ContentType, MediaType, Status},
    response::Redirect,
    routes, uri, Route, State,
};
use rocket_cache_response::{CacheControl, CacheResponse};

/// Favicons are small, so prefer the Medium converted size, then Small, then Large, falling
/// back to the original upload if none of those conversions exist.
const FAVICON_SIZE_PREFERENCE: [MediaConversion; 3] = [
    MediaConversion::Medium,
    MediaConversion::Small,
    MediaConversion::Large,
];

/// shields.io badge path segments are split on unescaped `-`, with a literal hyphen escaped as
/// `--`. Percent-encoding a hyphen to `%2D` doesn't work: it's decoded back to `-` before that
/// split happens, so it's indistinguishable from a real separator and corrupts the badge. This
/// set leaves `-` unencoded so callers can pre-escape hyphens as `--` and have them survive.
const SHIELD_LABEL_TEXT: &AsciiSet = &NON_ALPHANUMERIC.remove(b'-');

lazy_static! {
    pub static ref INFORMATIONAL_PAGES: Vec<Route> = routes![
        info_shield,
        docs,
        documentation,
        protocol_docs,
        favicon_ico,
        favicon_png
    ];
}

#[rocket::get("/info_shield")]
async fn info_shield(state: &State<RocketState>) -> Result<CacheResponse<Redirect>, Status> {
    let service_version = get_service_version().unwrap().version;

    let mut conn = state.pool.get().unwrap();
    let server_configuration = get_server_configuration_proto(&mut conn).unwrap();
    let server_info = server_configuration.server_info.as_ref().unwrap();
    let server_name = server_info.name.as_ref().unwrap();
    let colors = server_info.colors.as_ref().unwrap();
    let primary_color_int = colors.primary.unwrap();
    let nav_color_int = colors.navigation.unwrap();
    let mut primary_color = format!("{:x}", primary_color_int);
    while primary_color.len() < 6 {
        primary_color = format!("0{}", primary_color);
    }
    while primary_color.len() > 6 {
        primary_color = format!("{}", &primary_color[1..]);
    }
    let mut nav_color = format!("{:x}", nav_color_int);
    while nav_color.len() < 6 {
        nav_color = format!("0{}", nav_color);
    }
    while nav_color.len() > 6 {
        nav_color = format!("{}", &nav_color[1..]);
    }

    let encoded_server_name =
        utf8_percent_encode(&server_name.replace('-', "--"), SHIELD_LABEL_TEXT).to_string();

    let logo_media_id = server_info
        .logo
        .as_ref()
        .map(|l| l.square_media_id.clone())
        .flatten();
    let logo_media_data_url = match logo_media_id {
        Some(ref logo_media_id) => {
            let logo_data = load_media_file_data(logo_media_id, None, state).await?;
            let content_type = logo_data.0;
            match content_type.to_string().as_str() {
                "image/svg+xml" => {
                    let named_filename =
                        &logo_data.1.path().as_os_str().to_str().unwrap().to_string();
                    let logo_file = std::fs::File::open(named_filename).unwrap();
                    let logo_bytes = std::io::Read::bytes(logo_file)
                        .collect::<Result<Vec<u8>, _>>()
                        .unwrap();
                    let media_data_url = format!(
                        "data:{};base64,{}",
                        content_type,
                        BASE64_STANDARD.encode(&logo_bytes)
                    );
                    Some(media_data_url)
                }
                _ => None,
            }
        }
        None => None,
    };
    let encoded_logo = match logo_media_data_url {
        Some(logo_media_data_url) => {
            let encoded_logo =
                utf8_percent_encode(&logo_media_data_url, NON_ALPHANUMERIC).to_string();
            Some(encoded_logo)
        }
        None => None,
    };

    match encoded_logo {
        Some(encoded_logo) => Ok(CacheResponse::no_store(Redirect::temporary(format!(
            "https://img.shields.io/badge/{}-v{}-information?labelColor={}&color={}&logo={}",
            encoded_server_name,
            service_version.replace("-", "--"),
            primary_color,
            nav_color,
            encoded_logo
        )))),
        None => Ok(CacheResponse::no_store(Redirect::temporary(format!(
            "https://img.shields.io/badge/{}-v{}-information?labelColor={}&color={}",
            encoded_server_name,
            service_version.replace("-", "--"),
            primary_color,
            nav_color
        )))),
    }
}

#[rocket::get("/documentation")]
fn documentation() -> Redirect {
    Redirect::to(uri!(docs))
}

#[rocket::get("/docs")]
fn docs() -> Redirect {
    Redirect::to(uri!(protocol_docs))
}

#[rocket::get("/docs/protocol")]
pub async fn protocol_docs() -> CacheResponse<Result<NamedFile, Status>> {
    docs_path("protocol.html").await
}

async fn docs_path(path: &str) -> CacheResponse<Result<NamedFile, Status>> {
    let result = match NamedFile::open(format!("opt/docs/{}", path)).await {
        Ok(file) => Ok(file),
        Err(_) => match NamedFile::open(format!("../docs/{}", path)).await {
            Ok(file) => Ok(file),
            Err(e) => Err(e),
        },
    };
    CacheResponse::public(
        result.map_err(|e| {
            log::error!("docs_path: {:?}", e);
            Status::NotFound
        }),
        60,
    )
}

#[rocket::get("/favicon.ico")]
async fn favicon_ico<'a>(
    state: &State<RocketState>,
) -> Result<CacheResponse<(ContentType, NamedFile)>, Status> {
    let mut conn = state.pool.get().unwrap();
    let configuration = get_server_configuration_proto(&mut conn).unwrap();
    let logo = configuration
        .server_info
        .unwrap_or(ServerInfo {
            ..Default::default()
        })
        .logo
        .unwrap_or(ServerLogo {
            ..Default::default()
        })
        .square_media_id;
    match logo {
        None => {
            let media_type = ContentType(
                MediaType::from_str("image/x-icon").map_err(|_| Status::ExpectationFailed)?,
            );
            let favicon_file = match NamedFile::open("opt/tamagui_web/favicon.ico").await {
                Ok(file) => file,
                Err(_) => {
                    match NamedFile::open("../frontends/tamagui/apps/next/out/favicon.ico").await {
                        Ok(file) => file,
                        Err(_) => return Err(Status::ExpectationFailed),
                    }
                }
            };
            Ok(CacheResponse::new(
                (media_type, favicon_file),
                CacheControl {
                    must_revalidate: true,
                    ..CacheControl::public(3600 * 12)
                },
            ))
        }
        Some(square_media_id) => {
            let data =
                load_media_file_data_preferring(&square_media_id, &FAVICON_SIZE_PREFERENCE, state)
                    .await?;
            let mut content_type = &data.0;
            let mut named_filename = &data.1.path().as_os_str().to_str().unwrap().to_string();
            let ico_filename = format!(
                "{}/png-converted-favicon.ico",
                state.tempdir.path().display()
            );
            let ico_content_type = &ContentType(
                MediaType::from_str("image/x-icon").map_err(|_| Status::ExpectationFailed)?,
            );
            // Convert PNG icons to ICO
            if content_type.to_string().ends_with("png") {
                convert_png_to_ico(named_filename, &ico_filename, state.tempdir.path())?;
                named_filename = &ico_filename;
                content_type = ico_content_type
            }

            Ok(CacheResponse::new(
                (
                    content_type.to_owned(),
                    open_named_file(named_filename).await?,
                ),
                CacheControl {
                    must_revalidate: true,
                    ..CacheControl::public(3600 * 12)
                },
            ))
        }
    }
}

#[rocket::get("/favicon.png")]
async fn favicon_png<'a>(
    state: &State<RocketState>,
) -> Result<CacheResponse<(ContentType, NamedFile)>, Status> {
    let mut conn = state.pool.get().unwrap();
    let configuration = get_server_configuration_proto(&mut conn).unwrap();
    let logo = configuration
        .server_info
        .unwrap_or(ServerInfo {
            ..Default::default()
        })
        .logo
        .unwrap_or(ServerLogo {
            ..Default::default()
        })
        .square_media_id;
    match logo {
        None => {
            let favicon_ico_path = if std::path::Path::new("tamagui_web/favicon.ico").exists() {
                "tamagui_web/favicon.ico".to_string()
            } else if std::path::Path::new("opt/tamagui_web/favicon.ico").exists() {
                "opt/tamagui_web/favicon.ico".to_string()
            } else if std::path::Path::new("../frontends/tamagui/apps/next/out/favicon.ico")
                .exists()
            {
                "../frontends/tamagui/apps/next/out/favicon.ico".to_string()
            } else {
                return Err(Status::ExpectationFailed);
            };
            let png_filename = format!("{}/default-favicon.png", state.tempdir.path().display());
            convert_ico_to_png(&favicon_ico_path, &png_filename)?;

            Ok(CacheResponse::new(
                (ContentType::PNG, open_named_file(&png_filename).await?),
                CacheControl {
                    must_revalidate: true,
                    ..CacheControl::public(3600 * 12)
                },
            ))
        }
        Some(square_media_id) => {
            let data =
                load_media_file_data_preferring(&square_media_id, &FAVICON_SIZE_PREFERENCE, state)
                    .await?;
            let mut content_type = data.0;
            let mut named_filename = data.1.path().as_os_str().to_str().unwrap().to_string();

            // Convert ICO icons to PNG
            if content_type.to_string().ends_with("ico") {
                let png_filename = format!(
                    "{}/ico-converted-favicon.png",
                    state.tempdir.path().display()
                );
                convert_ico_to_png(&named_filename, &png_filename)?;
                named_filename = png_filename;
                content_type = ContentType::PNG;
            }

            Ok(CacheResponse::new(
                (content_type, open_named_file(&named_filename).await?),
                CacheControl {
                    must_revalidate: true,
                    ..CacheControl::public(3600 * 12)
                },
            ))
        }
    }
}

/// Sizes actually encodable in an ICO directory entry: width/height there are single bytes, with
/// 0 standing in for 256, so 256px is the hard ceiling. Packing a larger PNG in as-is (as this
/// used to) still "succeeds", but `ico`'s writer silently clamps the declared size to 256 while
/// the embedded PNG stays full resolution -- a mismatch most browsers/OSes refuse to load.
const FAVICON_ICO_SIZES: [u32; 6] = [16, 32, 48, 64, 128, 256];

/// Packs `png_path` into a proper multi-resolution ICO at `ico_path`, resizing down to each of
/// `FAVICON_ICO_SIZES` via ImageMagick first (see that const's doc for why resizing is required).
/// `tempdir` holds the per-size intermediate PNGs. Falls back to a single unresized frame if
/// ImageMagick isn't installed -- valid only if `png_path` already happens to be <=256px.
fn convert_png_to_ico(png_path: &str, ico_path: &str, tempdir: &Path) -> Result<(), Status> {
    let mut icon_dir = ico::IconDir::new(ico::ResourceType::Icon);
    match ImageMagick::detect() {
        Some(imagemagick) => {
            for size in FAVICON_ICO_SIZES {
                let frame_path = tempdir.join(format!("favicon-{size}.png"));
                imagemagick
                    .resize_to_truecolor_png(Path::new(png_path), &frame_path, size)
                    .map_err(|_| Status::ExpectationFailed)?;
                let frame_file =
                    std::fs::File::open(&frame_path).map_err(|_| Status::ExpectationFailed)?;
                let image =
                    ico::IconImage::read_png(frame_file).map_err(|_| Status::ExpectationFailed)?;
                icon_dir.add_entry(
                    ico::IconDirEntry::encode(&image).map_err(|_| Status::ExpectationFailed)?,
                );
            }
        }
        None => {
            let source_file =
                std::fs::File::open(png_path).map_err(|_| Status::ExpectationFailed)?;
            let image =
                ico::IconImage::read_png(source_file).map_err(|_| Status::ExpectationFailed)?;
            icon_dir.add_entry(
                ico::IconDirEntry::encode(&image).map_err(|_| Status::ExpectationFailed)?,
            );
        }
    }
    let ico_file = std::fs::File::create(ico_path).map_err(|_| Status::ExpectationFailed)?;
    icon_dir
        .write(ico_file)
        .map_err(|_| Status::ExpectationFailed)
}

/// Decodes the largest frame in an ICO file and writes it out as a PNG.
fn convert_ico_to_png(ico_path: &str, png_path: &str) -> Result<(), Status> {
    let ico_file = std::fs::File::open(ico_path).map_err(|_| Status::ExpectationFailed)?;
    let icon_dir = ico::IconDir::read(ico_file).map_err(|_| Status::ExpectationFailed)?;
    let entry = icon_dir
        .entries()
        .iter()
        .max_by_key(|entry| entry.width())
        .ok_or(Status::ExpectationFailed)?;
    let image = entry.decode().map_err(|_| Status::ExpectationFailed)?;
    let png_file = std::fs::File::create(png_path).map_err(|_| Status::ExpectationFailed)?;
    image
        .write_png(png_file)
        .map_err(|_| Status::ExpectationFailed)
}
