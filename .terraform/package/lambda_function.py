import json
import os
import subprocess
import boto3
import tempfile
import shutil
from urllib.parse import urlparse


def download_video(url, output_path):
    """Download video using yt-dlp"""
    try:
        subprocess.run(
            ["yt-dlp", "-f", "best", "-o", output_path, url],  # Download best quality
            check=True,
        )
        return True
    except subprocess.CalledProcessError as e:
        print(f"Error downloading video: {e}")
        return False


def upload_to_s3(file_path, s3_key):
    """Upload file to S3"""
    s3_client = boto3.client("s3")
    try:
        s3_client.upload_file(file_path, os.environ["S3_BUCKET"], s3_key)
        return True
    except Exception as e:
        print(f"Error uploading to S3: {e}")
        return False


def lambda_handler(event, context):
    print("Received Event:", json.dumps(event, indent=2))

    # Get the origin from the request
    origin = event.get("headers", {}).get("origin", "")

    # Only allow specific origins
    allowed_origins = ["http://localhost:5173", "http://127.0.0.1:5173"]

    # Common CORS headers
    cors_headers = {
        "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Amz-Date, X-Api-Key, X-Amz-Security-Token",
        "Access-Control-Allow-Credentials": "true",
        "Access-Control-Max-Age": "300",
    }

    # If origin is present, validate it
    if origin:
        if origin not in allowed_origins:
            return {
                "statusCode": 403,
                "headers": {
                    **cors_headers,
                    "Access-Control-Allow-Origin": allowed_origins[0],
                },
                "body": json.dumps({"message": "Origin not allowed"}),
            }
        cors_headers["Access-Control-Allow-Origin"] = origin
    else:
        # For requests without origin (like Postman), use the first allowed origin
        cors_headers["Access-Control-Allow-Origin"] = allowed_origins[0]

    # Get the HTTP method from the event
    http_method = event.get("requestContext", {}).get("http", {}).get("method", "")
    print("HTTP Method:", http_method)

    # Handle CORS Preflight (OPTIONS Request)
    if http_method == "OPTIONS":
        return {
            "statusCode": 204,
            "headers": cors_headers,
            "body": "",
        }

    # Handle Actual Request
    try:
        body = json.loads(event.get("body", "{}"))
        video_url = body.get("video_url")
        email = body.get("email")

        if not video_url or not email:
            return {
                "statusCode": 400,
                "headers": cors_headers,
                "body": json.dumps(
                    {"message": "Missing video_url or email in request body"}
                ),
            }

        # Create a temporary directory for video processing
        with tempfile.TemporaryDirectory() as temp_dir:
            # Generate a unique filename
            video_filename = f"{os.path.basename(urlparse(video_url).path)}"
            if not video_filename:
                video_filename = "video.mp4"

            # Create email-based folder path
            email_folder = email.replace("@", "_at_").replace(".", "_dot_")
            s3_key = f"{email_folder}/{video_filename}"
            local_path = os.path.join(temp_dir, video_filename)

            # Download the video
            if not download_video(video_url, local_path):
                return {
                    "statusCode": 500,
                    "headers": cors_headers,
                    "body": json.dumps({"message": "Failed to download video"}),
                }

            # Upload to S3
            if not upload_to_s3(local_path, s3_key):
                return {
                    "statusCode": 500,
                    "headers": cors_headers,
                    "body": json.dumps({"message": "Failed to upload video to S3"}),
                }

            return {
                "statusCode": 200,
                "headers": cors_headers,
                "body": json.dumps(
                    {
                        "message": "Success",
                        "s3_key": s3_key,
                        "bucket": os.environ["S3_BUCKET"],
                    }
                ),
            }

    except Exception as e:
        print(f"Error processing request: {e}")
        return {
            "statusCode": 500,
            "headers": cors_headers,
            "body": json.dumps({"message": f"Internal server error: {str(e)}"}),
        }
