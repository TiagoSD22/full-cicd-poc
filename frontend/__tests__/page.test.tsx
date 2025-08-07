import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom';
import axios from 'axios';
import Home from '../src/app/page';

// Mock axios
jest.mock('axios');
const mockedAxios = axios as jest.Mocked<typeof axios>;

// Mock Next.js environment
process.env.NEXT_PUBLIC_BACKEND_URL = 'http://localhost:5000';

describe('Home Page', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  test('renders the page title', () => {
    render(<Home />);
    expect(screen.getByText('Frontend Application')).toBeInTheDocument();
  });

  test('displays loading state initially', () => {
    mockedAxios.get.mockImplementation(() => new Promise(() => {})); // Never resolves
    render(<Home />);
    expect(screen.getByText('Loading...')).toBeInTheDocument();
  });

  test('displays message from backend API', async () => {
    const mockResponse = { data: { message: 'Hello' } };
    mockedAxios.get.mockResolvedValueOnce(mockResponse);

    render(<Home />);

    await waitFor(() => {
      expect(screen.getByTestId('message')).toBeInTheDocument();
      expect(screen.getByTestId('message')).toHaveTextContent('Hello');
    });

    expect(mockedAxios.get).toHaveBeenCalledWith('http://localhost:5000/api/hello');
  });

  test('displays error message when API call fails', async () => {
    mockedAxios.get.mockRejectedValueOnce(new Error('Network Error'));

    render(<Home />);

    await waitFor(() => {
      expect(screen.getByText('Failed to fetch message from backend')).toBeInTheDocument();
    });
  });

  test('refresh button calls API again', async () => {
    const mockResponse = { data: { message: 'Hello' } };
    mockedAxios.get.mockResolvedValue(mockResponse);

    render(<Home />);

    // Wait for initial load
    await waitFor(() => {
      expect(screen.getByTestId('message')).toBeInTheDocument();
    });

    // Click refresh button
    const refreshButton = screen.getByTestId('refresh-button');
    fireEvent.click(refreshButton);

    await waitFor(() => {
      expect(mockedAxios.get).toHaveBeenCalledTimes(2);
    });
  });

  test('refresh button is disabled during loading', async () => {
    mockedAxios.get.mockImplementation(() => new Promise(() => {})); // Never resolves
    
    render(<Home />);
    
    const refreshButton = screen.getByTestId('refresh-button');
    expect(refreshButton).toBeDisabled();
  });
});
