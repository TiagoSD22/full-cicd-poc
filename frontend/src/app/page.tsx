'use client';

import { useState, useEffect } from 'react';
import axios from 'axios';
import styles from './page.module.css';

export default function Home() {
  const [message, setMessage] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const fetchMessage = async () => {
    setLoading(true);
    setError('');
    
    try {
      const backendUrl = process.env.NEXT_PUBLIC_BACKEND_URL || 'http://localhost:5000';
      const response = await axios.get(`${backendUrl}/api/hello`);
      setMessage(response.data.message);
    } catch (err) {
      setError('Failed to fetch message from backend');
      console.error('Error fetching message:', err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchMessage();
  }, []);

  return (
    <main className={styles.main}>
      <div className={styles.container}>
        <h1 className={styles.title}>Frontend Application</h1>
        
        <div className={styles.card}>
          <h2>Backend Message:</h2>
          {loading && <div className={styles.loading}>Loading...</div>}
          {error && <div className={styles.error}>{error}</div>}
          {message && !loading && !error && (
            <div className={styles.message} data-testid="message">
              {message}
            </div>
          )}
        </div>

        <button 
          className={styles.button} 
          onClick={fetchMessage}
          disabled={loading}
          data-testid="refresh-button"
        >
          Refresh Message
        </button>
      </div>
    </main>
  );
}
