import pytest
import json
from app import app

@pytest.fixture
def client():
    """Create a test client for the Flask application"""
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client

def test_hello_endpoint(client):
    """Test the hello API endpoint"""
    response = client.get('/api/hello')
    
    assert response.status_code == 200
    assert response.content_type == 'application/json'
    
    data = json.loads(response.data)
    assert data == {"message": "Hello"}

def test_health_endpoint(client):
    """Test the health check endpoint"""
    response = client.get('/health')
    
    assert response.status_code == 200
    assert response.content_type == 'application/json'
    
    data = json.loads(response.data)
    assert data == {"status": "healthy"}

def test_cors_headers(client):
    """Test that CORS headers are present"""
    response = client.get('/api/hello')
    
    assert 'Access-Control-Allow-Origin' in response.headers

def test_invalid_endpoint(client):
    """Test invalid endpoint returns 404"""
    response = client.get('/api/invalid')
    
    assert response.status_code == 404
