FROM python:3.12-slim
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 BOIPATH_COVER_CACHE=/home/app/.cover-cache
WORKDIR /srv/boipath
COPY requirements.txt .
RUN python -m pip install --no-cache-dir -r requirements.txt && useradd --create-home app
COPY boipath ./boipath
COPY migrations ./migrations
COPY seed.json .
USER app
EXPOSE 8000
CMD ["uvicorn", "boipath.app:app", "--host", "0.0.0.0", "--port", "8000"]
