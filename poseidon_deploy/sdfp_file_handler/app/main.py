from __future__ import print_function
import argparse
import io
import os
import json
import logging
import shutil
import socket
import subprocess
import time
import re
from datetime import datetime

import httplib2
from dotenv import load_dotenv
load_dotenv()

from app import models, database, db_functions
from googleapiclient.discovery import build
from googleapiclient.http import MediaIoBaseDownload, MediaFileUpload
from oauth2client.service_account import ServiceAccountCredentials

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

# Ensure DB models are created when this module is imported
models.database.Base.metadata.create_all(bind=database.engine)


def execute_with_retries(request, retries=3, delay=1):
    last_exc = None
    for attempt in range(1, retries + 1):
        try:
            return request.execute()
        except (OSError, socket.gaierror, httplib2.HttpLib2Error) as exc:
            last_exc = exc
            logger.warning("Request attempt %s/%s failed: %s", attempt, retries, exc)
            if attempt == retries:
                raise
            time.sleep(delay)
    raise last_exc


def create_drive_client(json_secret=None):
    """
    Create and return a Google Drive API client (v3).
    - json_secret: optional dict or JSON string with service-account key; otherwise reads GOOGLE_JSON_KEY env var.
    Raises RuntimeError if no credentials provided.
    """
    scope = ["https://www.googleapis.com/auth/drive"]

    if json_secret is None:
        raw = os.environ.get("GOOGLE_JSON_KEY")
        if not raw:
            raise RuntimeError("No GOOGLE_JSON_KEY env var and no json_secret provided")
        json_secret = json.loads(raw)

    if isinstance(json_secret, str):
        json_secret = json.loads(json_secret)

    # Normalize private_key newlines if present
    if "private_key" in json_secret and isinstance(json_secret["private_key"], str):
        json_secret["private_key"] = json_secret["private_key"].replace("\\n", "\n")

    credentials = ServiceAccountCredentials.from_json_keyfile_dict(keyfile_dict=json_secret, scopes=scope)
    drive = build("drive", "v3", credentials=credentials)
    return drive


def get_db_session():
    """
    Return a new SQLAlchemy Session from the app's database module.
    Caller is responsible for closing the session.
    """
    return database.SessionLocal()


def get_db():
    """
    Generator-compatible DB dependency (yields a session, closes on finish).
    Useful if you later reintroduce FastAPI endpoints.
    """
    db = database.SessionLocal()
    try:
        yield db
    finally:
        db.close()


def print_drive_listing(drive, page_size=10):
    """Print a simple Linux-like listing of files and folders in a Google Drive folder."""
    folder_id = os.environ.get("GOOGLE_DRIVE_FOLDER_ID")
    if not folder_id:
        raise RuntimeError("GOOGLE_DRIVE_FOLDER_ID is not set in the environment")

    folder_info = execute_with_retries(
        drive.files().get(
            fileId=folder_id,
            fields="id, name, mimeType",
            supportsAllDrives=True,
        )
    )
    logger.info("Listing contents of folder: %s (%s)", folder_info.get("name"), folder_info.get("id"))

    results = execute_with_retries(
        drive.files()
        .list(
            pageSize=page_size,
            fields="nextPageToken, files(id, name, mimeType, size)",
            q=f"trashed=false and '{folder_id}' in parents",
            supportsAllDrives=True,
            includeItemsFromAllDrives=True,
        )
    )
    items = results.get("files", [])

    if not items:
        logger.info("No files found.")
        return

    logger.info("Listing up to %s Google Drive items in folder %s:", page_size, folder_info.get("name"))
    for item in items:
        name = item.get("name", "<unknown>")
        mime_type = item.get("mimeType", "")
        is_folder = mime_type == "application/vnd.google-apps.folder"
        trailing = "/" if is_folder else ""
        size = item.get("size")
        size_label = "<dir>" if is_folder else f"{size}" if size is not None else "-"
        logger.info("%s  %s%s", size_label, name, trailing)

# def get_pending_photos(db, limit=10):
#     """Return the first pending photo_info rows ordered by DateTimeOriginalUTC."""
#     return (
#         db.query(models.photo_info_model)
#         .filter(models.photo_info_model.poseidonDone == False)
#         .order_by(models.photo_info_model.DateTimeOriginalUTC)
#         .limit(limit)
#         .all()
#     )
 
def get_pending_photos(db, limit=10):
    return (
        db.query(models.photo_info_model)
        .join(
            models.camera_locations_model,
            models.photo_info_model.camera_ID
            == models.camera_locations_model.camera_ID
        )
        .filter(models.photo_info_model.poseidonDone == False)
        .filter(models.camera_locations_model.doPoseidon == True)
        .order_by(models.photo_info_model.DateTimeOriginalUTC)
        .limit(limit)
        .all()
    )

def get_photo_date_str(photo):
    if photo.DateTimeOriginalUTC is None:
        return "unknown-date"

    try:
        return photo.DateTimeOriginalUTC.strftime("%Y-%m-%d")
    except AttributeError:
        return str(photo.DateTimeOriginalUTC)


def get_expected_drive_file_paths(photos, root_folder_id):
    """Return expected Google Drive paths for the given photo_info rows."""
    expected_paths = []
    for photo in photos:
        date_str = get_photo_date_str(photo)

        expected_paths.append({
            "drive_filename": photo.drive_filename,
            "camera_ID": photo.camera_ID,
            "DateTimeOriginalUTC": photo.DateTimeOriginalUTC,
            "expected_drive_path": f"{root_folder_id}/Images/{photo.camera_ID}/{date_str}/{photo.drive_filename}",
        })

    return expected_paths


def quote_drive_query_value(value):
    return value.replace("'", "\\'")


def list_drive_folder_items(drive, folder_id):
    """Return a map of child item names to (id, mimeType) under a Drive folder."""
    items = {}
    page_token = None
    while True:
        response = execute_with_retries(
            drive.files()
            .list(
                q=f"trashed=false and '{folder_id}' in parents",
                fields="nextPageToken, files(id, name, mimeType)",
                pageSize=1000,
                supportsAllDrives=True,
                includeItemsFromAllDrives=True,
                pageToken=page_token,
            )
        )
        for item in response.get("files", []):
            items[item["name"]] = (item["id"], item.get("mimeType"))
        page_token = response.get("nextPageToken")
        if not page_token:
            break
    return items


def get_drive_folder_id(drive, parent_folder_id, folder_name, cache, folder_contents_cache):
    """Return the ID of a named child folder, using caches when available."""
    cache_key = (parent_folder_id, folder_name)
    if cache_key in cache:
        return cache[cache_key]

    contents = folder_contents_cache.get(parent_folder_id)
    if contents is None:
        contents = list_drive_folder_items(drive, parent_folder_id)
        folder_contents_cache[parent_folder_id] = contents

    folder_id = None
    child = contents.get(folder_name)
    if child is not None and child[1] == "application/vnd.google-apps.folder":
        folder_id = child[0]

    cache[cache_key] = folder_id
    return folder_id


def get_or_create_folder(drive, parent_folder_id, folder_name, cache, folder_contents_cache):
    """Return the ID of a named child folder, creating it if necessary."""
    folder_id = get_drive_folder_id(drive, parent_folder_id, folder_name, cache, folder_contents_cache)
    if folder_id is not None:
        return folder_id

    body = {"name": folder_name, "mimeType": "application/vnd.google-apps.folder", "parents": [parent_folder_id]}
    req = drive.files().create(body=body, fields="id", supportsAllDrives=True)
    created = execute_with_retries(req)
    new_id = created.get("id")

    # refresh caches
    folder_contents_cache.pop(parent_folder_id, None)
    cache[(parent_folder_id, folder_name)] = new_id
    return new_id


def mark_missing_photos_done(drive, db, photos, root_folder_id):
    """Check expected Google Drive file paths and mark missing photos as done.

    Returns a tuple of (missing_photos, existing_photo_files).
    existing_photo_files is a list of tuples (photo, file_id).
    """
    missing = []
    existing = []
    folder_cache = {}
    folder_contents_cache = {}

    images_folder_id = get_drive_folder_id(drive, root_folder_id, "Images", folder_cache, folder_contents_cache)
    if images_folder_id is None:
        logger.info("Root Images folder not found under %s", root_folder_id)
        for photo in photos:
            photo.poseidonDone = True
            missing.append(photo)
        if missing:
            db.commit()
        return missing, existing

    photos_by_group = {}
    for photo in photos:
        date_str = get_photo_date_str(photo)
        key = (photo.camera_ID, date_str)
        photos_by_group.setdefault(key, []).append(photo)

    for (camera_id, date_str), group_photos in photos_by_group.items():
        camera_folder_id = get_drive_folder_id(drive, images_folder_id, camera_id, folder_cache, folder_contents_cache)
        if camera_folder_id is None:
            for photo in group_photos:
                expected_path = f"{root_folder_id}/Images/{camera_id}/{date_str}/{photo.drive_filename}"
                logger.info("Missing: %s", expected_path)
                photo.poseidonDone = True
                missing.append(photo)
            continue

        date_folder_id = get_drive_folder_id(drive, camera_folder_id, date_str, folder_cache, folder_contents_cache)
        if date_folder_id is None:
            for photo in group_photos:
                expected_path = f"{root_folder_id}/Images/{camera_id}/{date_str}/{photo.drive_filename}"
                logger.info("Missing: %s", expected_path)
                photo.poseidonDone = True
                missing.append(photo)
            continue

        date_folder_items = list_drive_folder_items(drive, date_folder_id)
        for photo in group_photos:
            expected_path = f"{root_folder_id}/Images/{camera_id}/{date_str}/{photo.drive_filename}"
            if photo.drive_filename not in date_folder_items:
                logger.info("Missing: %s", expected_path)
                photo.poseidonDone = True
                missing.append(photo)
            else:
                file_id = date_folder_items[photo.drive_filename][0]
                logger.info("Found: %s", photo.drive_filename)
                existing.append((photo, file_id))

    if missing:
        db.commit()
    return missing, existing


def normalize_site_name(camera_id):
    if camera_id is None:
        return ""
    return camera_id[4:] if camera_id.startswith("CAM_") else camera_id


def get_local_photo_path(repo_root, photo):
    site_name = normalize_site_name(photo.camera_ID)
    folder = os.path.join(repo_root, "data", "images-to-process", site_name, "orig_images")
    os.makedirs(folder, exist_ok=True)
    return os.path.join(folder, photo.drive_filename)


def download_drive_file(drive, file_id, dest_path):
    request = drive.files().get_media(fileId=file_id, supportsAllDrives=True)
    with open(dest_path, "wb") as fh:
        downloader = MediaIoBaseDownload(fh, request)
        done = False
        while not done:
            status, done = downloader.next_chunk()


def upload_file_to_drive(drive, parent_folder_id, local_path, filename):
    """Upload a local file to Drive under parent_folder_id. Returns the new file id."""
    media = MediaFileUpload(local_path, resumable=True)
    body = {"name": filename, "parents": [parent_folder_id]}
    req = drive.files().create(body=body, media_body=media, fields="id", supportsAllDrives=True)
    created = execute_with_retries(req)
    return created.get("id")


def upload_or_replace_file(drive, parent_folder_id, local_path, filename, existing_id=None):
    """Create a new file or replace existing file content on Drive.

    If existing_id is provided, performs `files().update(...)`, otherwise creates a new file.
    Returns the file id.
    """
    media = MediaFileUpload(local_path, resumable=True)
    if existing_id:
        req = drive.files().update(fileId=existing_id, media_body=media, fields="id", supportsAllDrives=True)
        created = execute_with_retries(req)
        return created.get("id")
    else:
        body = {"name": filename, "parents": [parent_folder_id]}
        req = drive.files().create(body=body, media_body=media, fields="id", supportsAllDrives=True)
        created = execute_with_retries(req)
        return created.get("id")


def normalize_camera_id_from_site(site_name):
    if site_name.startswith("CAM_"):
        return site_name
    return f"CAM_{site_name}"


def get_photo_info_for_overlay(db, overlay_filename):
    prefix = "segmap_overlay_"
    if not overlay_filename.startswith(prefix):
        return None
    drive_filename = overlay_filename[len(prefix):]
    return (
        db.query(models.photo_info_model)
        .filter(models.photo_info_model.drive_filename == drive_filename)
        .first()
    )


def get_datetime_timezone(photo):
    if photo is None:
        return os.environ.get("TIMEZONE", "EST")
    return photo.original_tz or os.environ.get("TIMEZONE", "EST")


def upload_overlay_to_api(local_path, camera_id, timezone):
    username = os.environ.get("username")
    password = os.environ.get("password")
    if not username or not password:
        raise RuntimeError("username and password must be set to upload overlays")

    api_url = "https://photos-sunnydayflood.apps.cloudapps.unc.edu/upload_overlay"
    cmd = [
        "curl",
        "--max-time", "300",
        "-X", "POST",
        api_url,
        "-F", f"file=@{local_path};type=image/jpeg",
        "-F", f"camera_ID={camera_id};type=*/*",
        "-F", f"timezone={timezone};type=*/*",
        "--basic",
        "--user", f"{username}:{password}",
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(
            "Overlay upload failed: exit %s, stderr=%s" % (result.returncode, result.stderr.strip())
        )
    return result.stdout.strip()


def download_pending_photos(drive, existing_photos, repo_root):
    downloaded = []
    for photo, file_id in existing_photos:
        dest_path = get_local_photo_path(repo_root, photo)
        filename = os.path.basename(dest_path)
        if os.path.exists(dest_path):
            logger.info("Already exists locally: %s", filename)
            downloaded.append(photo)
            continue

        logger.info("Downloading %s", photo.drive_filename)
        download_drive_file(drive, file_id, dest_path)
        downloaded.append(photo)
    return downloaded


def print_pending_photos(pending_photos):
    """Print pending photo_info rows returned by get_pending_photos."""
    if not pending_photos:
        logger.info("No pending photo_info rows found.")
        return

    logger.info("First %s pending photo_info rows ordered by DateTimeOriginalUTC:", len(pending_photos))
    for photo in pending_photos:
        values = [
            f"{column.name}={getattr(photo, column.name)}"
            for column in photo.__table__.columns
        ]
        logger.info("- %s", ", ".join(values))


def run_copyfiles():
    # Create Google Drive service client and database session
    drive = create_drive_client()
    #print_drive_listing(drive)     # For testing, to make sure we are connected to Google Drive.
    db = get_db_session()

    try:
        """Get the first N rows from the photo_info table where poseidonDone is False."""
        pending_photos = get_pending_photos(db, limit=100)
        #print_pending_photos(pending_photos)

        # get the specific google drive and set up the paths to the pending photos.
        root_folder_id = os.environ.get("GOOGLE_DRIVE_FOLDER_ID")
        if not root_folder_id:
            raise RuntimeError("GOOGLE_DRIVE_FOLDER_ID is not set in the environment")
        expected_paths = get_expected_drive_file_paths(pending_photos, root_folder_id)

        #logger.info("\nExpected Google Drive paths for pending photo_info rows:")
        #for item in expected_paths:
        #    logger.info("- %s", item['expected_drive_path'])

        logger.info("Checking existence of pending photos and marking missing ones as done:")
        missing_photos, existing_photos = mark_missing_photos_done(drive, db, pending_photos, root_folder_id)
        logger.info("Marked %s missing photo(s) as poseidonDone=True.", len(missing_photos))

        repo_root = os.environ.get("REPO_ROOT")
        if not repo_root:
            raise RuntimeError("REPO_ROOT is not set in the environment")
        repo_root = os.path.expanduser(os.path.expandvars(repo_root))

        downloaded_photos = download_pending_photos(drive, existing_photos, repo_root)
        logger.info("Downloaded %s pending photo(s) to local filesystem.", len(downloaded_photos))
    finally:
        db.close()


def run_storeresults():
    """Upload local result folders (overlays, labels, preds) to the ML Drive under poseidon/SITENAME/."""
    drive = create_drive_client()
    ml_root = os.environ.get("GOOGLE_ML_DRIVE_FOLDER_ID")
    if not ml_root:
        raise RuntimeError("GOOGLE_ML_DRIVE_FOLDER_ID is not set in the environment")

    repo_root = os.environ.get("REPO_ROOT")
    if not repo_root:
        raise RuntimeError("REPO_ROOT is not set in the environment")
    repo_root = os.path.expanduser(os.path.expandvars(repo_root))

    base_local = os.path.join(repo_root, "data", "images-to-process")
    if not os.path.isdir(base_local):
        logger.info("No images-to-process folder at %s", base_local)
        return

    folder_cache = {}
    folder_contents_cache = {}

    # ensure poseidon folder under ML root
    poseidon_folder_id = get_or_create_folder(drive, ml_root, "poseidon", folder_cache, folder_contents_cache)

    db = get_db_session()
    try:
        for site_name in sorted(os.listdir(base_local)):
            site_local = os.path.join(base_local, site_name)
            if not os.path.isdir(site_local):
                continue

            # create site folder under poseidon
            site_folder_id = get_or_create_folder(drive, poseidon_folder_id, site_name, folder_cache, folder_contents_cache)

            site_uploaded_files = []
            site_failed_uploads = []
            for sub in ("overlays", "labels", "preds"):
                local_sub = os.path.join(site_local, sub)
                if not os.path.isdir(local_sub):
                    logger.info("Skipping missing local folder: %s", local_sub)
                    continue

                # create remote subfolder under site
                remote_sub_id = get_or_create_folder(drive, site_folder_id, sub, folder_cache, folder_contents_cache)

                # Note: we create an extra date folder layer under the subfolder
                # and will list/create files under that date folder. Remote items
                # are listed per-date-folder below.

                for fname in sorted(os.listdir(local_sub)):
                    local_path = os.path.join(local_sub, fname)
                    if not os.path.isfile(local_path):
                        continue

                    # Resolve the date string to create/use a yyyy-mm-dd folder.
                    date_str = None

                    if sub == "overlays":
                        photo = get_photo_info_for_overlay(db, fname)
                        if photo is None:
                            logger.warning("No photo_info row found for overlay %s; skipping API upload", fname)
                            site_failed_uploads.append((sub, fname, local_path))
                            continue

                        # Use the photo's original timestamp if available
                        date_str = get_photo_date_str(photo)

                        camera_id = photo.camera_ID
                        timezone = get_datetime_timezone(photo)
                        try:
                            logger.info("Uploading overlay %s for camera_ID=%s to photo API", fname, camera_id)
                            upload_overlay_to_api(local_path, camera_id, timezone)
                        except Exception as exc:
                            logger.warning("Overlay upload failed for %s: %s", local_path, exc)
                            site_failed_uploads.append((sub, fname, local_path))
                            continue
                    else:
                        # Try to extract a YYYYMMDDHHMMSS timestamp from the filename.
                        m = re.search(r"(\d{14})", fname)
                        if m:
                            try:
                                dt = datetime.strptime(m.group(1), "%Y%m%d%H%M%S")
                                date_str = dt.strftime("%Y-%m-%d")
                            except Exception:
                                date_str = None

                        # Fallback: look up a photo_info row by drive_filename
                        if date_str is None:
                            photo = (
                                db.query(models.photo_info_model)
                                .filter(models.photo_info_model.drive_filename == fname)
                                .first()
                            )
                            if photo is not None:
                                date_str = get_photo_date_str(photo)

                    if not date_str:
                        date_str = "unknown-date"

                    # Ensure the date folder exists under the subfolder
                    date_folder_id = get_or_create_folder(drive, remote_sub_id, date_str, folder_cache, folder_contents_cache)

                    # get existing remote files in this date folder
                    date_remote_items = list_drive_folder_items(drive, date_folder_id)

                    existing = date_remote_items.get(fname)
                    existing_id = existing[0] if existing else None

                    action = "Updating" if existing_id else "Uploading"
                    logger.info("%s %s/%s/%s/%s -> ML Drive", action, site_name, sub, date_str, fname)
                    try:
                        new_id = upload_or_replace_file(drive, date_folder_id, local_path, fname, existing_id=existing_id)
                        folder_contents_cache.pop(date_folder_id, None)
                        site_uploaded_files.append((sub, fname, local_path))
                    except Exception as exc:
                        logger.warning("Failed to upload %s: %s", local_path, exc)
                        site_failed_uploads.append((sub, fname, local_path))

            if site_uploaded_files and not site_failed_uploads:
                if mark_site_done(db, site_name, repo_root):
                    logger.info("Site %s completed successfully; marked DB rows done.", site_name)
                else:
                    logger.warning("Site %s completed successfully but DB rows were not marked.", site_name)
            elif site_uploaded_files or site_failed_uploads:
                logger.info("Site %s had uploads but also failures; not marking done.", site_name)

            cleanup_site_workspace(site_name, repo_root)
    finally:
        db.close()


def mark_site_done(db, site_name, repo_root):
    """Mark photo_info rows as done for a site."""
    orig_folder = os.path.join(repo_root, "data", "images-to-process", site_name, "orig_images")
    orig_filenames = []
    if os.path.isdir(orig_folder):
        orig_filenames = [
            entry for entry in os.listdir(orig_folder)
            if os.path.isfile(os.path.join(orig_folder, entry))
        ]

    if not orig_filenames:
        logger.warning(
            "No original image files found for site %s under %s; cannot mark photo_info rows done.",
            site_name,
            orig_folder,
        )
        return False

    photos = (
        db.query(models.photo_info_model)
        .filter(models.photo_info_model.drive_filename.in_(orig_filenames))
        .all()
    )

    if not photos:
        logger.warning("No photo_info rows found for original images in site %s", site_name)
        return False

    for photo in photos:
        photo.poseidonDone = True
        logger.info("Marked poseidonDone=True for %s", photo.drive_filename)

    db.commit()
    return True


def cleanup_site_workspace(site_name, repo_root):
    """Remove the local workspace for a site under images-to-process."""
    site_folder = os.path.join(repo_root, "data", "images-to-process", site_name)
    if os.path.isdir(site_folder):
        try:
            shutil.rmtree(site_folder)
            logger.info("Removed site workspace %s", site_folder)
        except OSError as exc:
            logger.warning("Failed to remove site workspace %s: %s", site_folder, exc)


def parse_args():
    parser = argparse.ArgumentParser(description="Manage pending photo files and Drive operations.")
    parser.add_argument(
        "action",
        choices=["copyfiles", "storeresults"],
        help="Action to perform: copyfiles or storeresults",
    )
    return parser.parse_args()


def main():
    args = parse_args()
    if args.action == "copyfiles":
        run_copyfiles()
    elif args.action == "storeresults":
        run_storeresults()


if __name__ == "__main__":
    main()


__all__ = ["create_drive_client", "get_db_session", "get_db"]
