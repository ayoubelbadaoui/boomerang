import express from 'express';
import { processNotification } from '../../application/notificationService';
import { NotificationPayload } from '../../domain/notificationTypes';

export const app = express();
app.use(express.json());

app.get('/health', (_req, res) => {
  res.status(200).send({ status: 'ok' });
});

// Manual trigger to test push delivery via HTTPS callable/HTTP endpoint.
app.post('/notifications/test', async (req, res) => {
  try {
    const { userId, payload } = req.body as { userId?: string; payload?: NotificationPayload };
    if (!userId || !payload) {
      return res.status(400).send({ error: 'userId and payload are required' });
    }
    await processNotification(userId, payload);
    return res.status(200).send({ status: 'queued' });
  } catch (err) {
    console.error('[notifications] test endpoint failed', err);
    return res.status(500).send({ error: 'internal_error' });
  }
});
