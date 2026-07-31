import os

from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session

# from app import environment_vars
# environment_vars.set_env_vars()

SQLALCHEMY_DATABASE_URL = "postgresql://" + os.environ.get('POSTGRESQL_USER') + ":" + os.environ.get('POSTGRESQL_PASSWORD') + "@" + os.environ.get('POSTGRESQL_HOSTNAME') + "/" + os.environ.get('POSTGRESQL_DATABASE')

engine = create_engine(SQLALCHEMY_DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()