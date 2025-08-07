# Backend Flask API

Simple Flask API with a single GET endpoint that returns a JSON message.

## API Endpoints

- `GET /api/hello` - Returns `{"message": "Hello"}`
- `GET /health` - Health check endpoint

## Development Setup

```bash
pip install -r requirements.txt
python app.py
```

## Testing

```bash
pytest test_app.py -v
```

## Docker Build

```bash
docker build -t backend-api .
docker run -p 5000:5000 backend-api
```

## Environment Variables

- `FLASK_ENV`: Set to `development` for debug mode
- `PORT`: Server port (default: 5000)
