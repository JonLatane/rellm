use std::env;

use awscreds::Credentials;
// use awsregion::Region;
use s3::error::S3Error;
use s3::Region;
use s3::{Bucket, BucketConfiguration};

pub async fn get_and_test_bucket() -> Result<Box<Bucket>, S3Error> {
    let object_storage_access_key = env::var("OBJECT_STORAGE_ACCESS_KEY").map_err(|_| {
        S3Error::Credentials(awscreds::error::CredentialsError::MissingEnvVar(
            "OBJECT_STORAGE_ACCESS_KEY".to_string(),
            "".to_string(),
        ))
    })?;
    let object_storage_secret_key = env::var("OBJECT_STORAGE_SECRET_KEY").map_err(|_| {
        S3Error::Credentials(awscreds::error::CredentialsError::MissingEnvVar(
            "OBJECT_STORAGE_SECRET_KEY".to_string(),
            "".to_string(),
        ))
    })?;

    let bucket = get_bucket()?;

    let s3_path = "test.file";
    let test = b"I'm going to S3!";

    // `Bucket` is just a config struct (name/region/credentials), not a live connection, so
    // it doesn't need to be reconstructed after creating the bucket below -- the same `bucket`
    // can be reused for the retried `put_object`.
    let response_data = match bucket.put_object(s3_path, test).await {
        Err(e) if e.to_string().contains("NoSuchBucket") => {
            log::warn!("Object storage bucket does not exist, attempting to create");
            Bucket::create_with_path_style(
                bucket.name.as_str(),
                bucket.region.clone(),
                Credentials {
                    access_key: Some(object_storage_access_key.to_owned()),
                    secret_key: Some(object_storage_secret_key.to_owned()),
                    security_token: None,
                    expiration: None,
                    session_token: None,
                },
                BucketConfiguration::public(),
            )
            .await
            .map_err(|e| {
                log::error!("Failed to create object storage Bucket: {:?}", e);
                e
            })?;
            log::warn!("Object storage bucket created");
            bucket.put_object(s3_path, test).await
        }
        other => other,
    };
    assert_eq!(response_data?.status_code(), 200);

    let response_data = bucket.get_object(s3_path).await?;
    assert_eq!(response_data.status_code(), 200);
    assert_eq!(test, response_data.as_slice());

    let (head_object_result, code) = bucket.head_object(s3_path).await?;
    assert_eq!(code, 200);
    assert_eq!(
        head_object_result.content_type.unwrap_or_default(),
        "application/octet-stream".to_owned()
    );

    let response_data = bucket.delete_object(s3_path).await?;
    assert_eq!(response_data.status_code(), 204);
    Ok(bucket)
}

fn get_bucket() -> Result<Box<Bucket>, S3Error> {
    let object_storage_endpoint = env::var("OBJECT_STORAGE_ENDPOINT").map_err(|_| {
        S3Error::Credentials(awscreds::error::CredentialsError::MissingEnvVar(
            "OBJECT_STORAGE_ENDPOINT".to_string(),
            "".to_string(),
        ))
    })?;
    let object_storage_region = env::var("OBJECT_STORAGE_REGION").map_err(|_| {
        S3Error::Credentials(awscreds::error::CredentialsError::MissingEnvVar(
            "OBJECT_STORAGE_REGION".to_string(),
            "".to_string(),
        ))
    })?;
    let object_storage_bucket = env::var("OBJECT_STORAGE_BUCKET").map_err(|_| {
        S3Error::Credentials(awscreds::error::CredentialsError::MissingEnvVar(
            "OBJECT_STORAGE_BUCKET".to_string(),
            "".to_string(),
        ))
    })?;
    let object_storage_access_key = env::var("OBJECT_STORAGE_ACCESS_KEY").map_err(|_| {
        S3Error::Credentials(awscreds::error::CredentialsError::MissingEnvVar(
            "OBJECT_STORAGE_ACCESS_KEY".to_string(),
            "".to_string(),
        ))
    })?;
    let object_storage_secret_key = env::var("OBJECT_STORAGE_SECRET_KEY").map_err(|_| {
        S3Error::Credentials(awscreds::error::CredentialsError::MissingEnvVar(
            "OBJECT_STORAGE_SECRET_KEY".to_string(),
            "".to_string(),
        ))
    })?;
    Ok(Bucket::new(
        &object_storage_bucket,
        Region::Custom {
            region: object_storage_region.to_owned(),
            endpoint: object_storage_endpoint.to_owned(),
        },
        Credentials {
            access_key: Some(object_storage_access_key.to_owned()),
            secret_key: Some(object_storage_secret_key.to_owned()),
            security_token: None,
            expiration: None,
            session_token: None,
        },
    )?
    .with_path_style())
}
