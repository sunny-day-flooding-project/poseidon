from sqlalchemy import Boolean, Column, String, Float, DateTime, Interval, text

from app import database


class photo_info_model(database.Base):
    __tablename__ = "photo_info"

    drive_filename = Column(String, primary_key=True, index=True)
    camera_ID = Column(String, index=True)
    FileSize = Column(Float, index=True)
    DateTimeOriginal = Column(String, index=True)
    original_tz = Column(String, index=True)
    DateTimeOriginalUTC = Column(DateTime, index=True)
    poseidonDone = Column(Boolean, index=True, nullable=False, server_default=text('false'))
    poseidonWaterDetected = Column(Boolean, index=True, nullable=False, server_default=text('false'))
    poseidonMaxDepth = Column(Float, index=True, nullable=False, server_default=text('0'))
    poseidonFloodDuration = Column(Interval, index=True, nullable=False, server_default=text("'0 seconds'::interval"))

class camera_locations_model(database.Base):
    __tablename__ = "camera_locations"

    place = Column(String, primary_key=True, index=True)
    camera_ID = Column(String, primary_key=True,index=True)
    lng = Column(Float, index=True)
    lat = Column(Float, index=True)
    camera_label = Column(String, index=True)
    sensor_ID = Column(String, index=True)
    sendto_webcoos = Column(Boolean, index=True)
    doPoseidon = Column(Boolean, index=True)
    
