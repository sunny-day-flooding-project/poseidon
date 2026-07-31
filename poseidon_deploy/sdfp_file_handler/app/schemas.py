# from typing import List, Optional
import datetime

from pydantic import BaseModel


class photo_info_model_base(BaseModel):
    drive_filename = str
    camera_ID = str
    # FileSize = float
    # DateTimeOriginal = str
    # original_tz = str
    # DateTimeOriginalUTC = datetime.datetime
    # poseidonDone = bool
    # poseidonWaterDetected = bool
    # poseidonMaxDepth = float
    # poseidonFloodDuration = datetime.timedelta


class photo_info(photo_info_model_base):
    class Config:
        orm_mode = True
