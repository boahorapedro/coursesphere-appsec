FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
RUN useradd --system --uid 10001 --no-create-home app
COPY --chown=app:app . .
RUN chmod +x entrypoint.sh && chown app:app /app
USER app
EXPOSE 5000
ENTRYPOINT ["./entrypoint.sh"]
CMD ["flask", "--app", "endpoints", "run", "--host", "0.0.0.0", "--port", "5000"]