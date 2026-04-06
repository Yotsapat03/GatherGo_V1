// ====================================
// server.cjs Backend QR Upload Endpoint
// ====================================
// Add this code snippet to backend/server.cjs

// LOCATION 1: After app initialization (~line 40, after app.use(cors()))
// ────────────────────────────────────────────────────────────────────

// ✅ Enhance CORS for Flutter Web
// Replace the existing app.use(cors()) with:
const corsOptions = {
  origin: [
    'http://localhost:3000',      // Backend itself
    'http://127.0.0.1:3000',
    'http://localhost:59968',     // Chrome DevTools default
    'http://localhost:8080',      // Flutter web default port
    'http://localhost:5000',      // Alternative web port
    'http://localhost',           // Local machine
    // In production, add your actual domain:
    // 'https://yourdomain.com',
  ],
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Accept', 'Authorization'],
};

app.use(cors(corsOptions));

// ====================================
// LOCATION 2: Add QR upload directory
// AFTER uploadDir creation (~line 462)
// ====================================

const qrUploadDir = path.join(uploadDir, 'qr');
if (!fs.existsSync(qrUploadDir)) fs.mkdirSync(qrUploadDir, { recursive: true });

// ====================================
// LOCATION 3: Create multer middleware for QR
// AFTER existing upload middleware (~line 480)
// ====================================

// ✅ Dedicated multer for QR uploads
const qrStorage = multer.diskStorage({
  destination: (_, __, cb) => cb(null, qrUploadDir),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname) || '.png';
    const eventId = req.params.id || 'unknown';
    cb(null, `qr_event_${eventId}_${Date.now()}${ext}`);
  },
});

const uploadQR = multer({
  storage: qrStorage,
  limits: { fileSize: 5 * 1024 * 1024 }, // 5MB max
  fileFilter: (req, file, cb) => {
    const allowedMimes = ['image/jpeg', 'image/png', 'image/gif', 'image/webp'];
    if (allowedMimes.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error('Only image files are allowed (jpeg, png, gif, webp)'));
    }
  },
});

// ====================================
// LOCATION 4: Add QR upload endpoint
// AFTER existing upload endpoints (~line 510)
// ====================================

/**
 * =====================================================
 * ✅ Admin: Upload/Update Payment QR Code
 * POST /api/admin/events/:id/qr  (multipart/form-data)
 * 
 * Body:
 *   - file: image file (QR code)
 *   - payment_method: (optional) 'promptPay', 'aliPay', etc.
 * 
 * Response:
 *   {
 *     "id": event_id,
 *     "qr_url": "/uploads/qr/qr_event_123_1708345667123.png",
 *     "qr_payment_method": "promptPay",
 *     "message": "QR code updated successfully"
 *   }
 * =====================================================
 */
app.post('/api/admin/events/:id/qr', uploadQR.single('file'), async (req, res) => {
  const client = await pool.connect();
  try {
    const eventId = parseInt(req.params.id, 10);

    if (!eventId || Number.isNaN(eventId)) {
      return res.status(400).json({ message: 'Invalid event ID' });
    }

    if (!req.file) {
      return res.status(400).json({ message: 'No file uploaded' });
    }

    // ✅ Build the URL that Flutter will use
    // For local development: /uploads/qr/qr_event_123_timestamp.png
    // Frontend will combine with baseUrl (http://localhost:3000)
    const qrUrl = `/uploads/qr/${req.file.filename}`;
    const paymentMethod = (req.body.payment_method || 'promptPay').trim();

    await client.query('BEGIN');

    // ✅ Update event with QR URL
    const updateRes = await client.query(
      `
      UPDATE events
      SET 
        qr_url = $1,
        qr_payment_method = $2,
        updated_at = NOW()
      WHERE id = $3
      RETURNING 
        id, 
        title, 
        qr_url, 
        qr_payment_method,
        updated_at
      `,
      [qrUrl, paymentMethod, eventId]
    );

    if (updateRes.rowCount === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ message: 'Event not found' });
    }

    await client.query('COMMIT');

    const updatedEvent = updateRes.rows[0];

    return res.status(200).json({
      message: 'QR code uploaded successfully',
      id: updatedEvent.id,
      title: updatedEvent.title,
      qr_url: updatedEvent.qr_url,
      qr_payment_method: updatedEvent.qr_payment_method,
      updated_at: updatedEvent.updated_at,
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('❌ QR upload error:', err);
    return res.status(500).json({
      message: 'Server error',
      error: err.message,
    });
  } finally {
    client.release();
  }
});

// ====================================
// LOCATION 5: Get Event with QR (optional)
// =====================================================
// Make sure GET /api/big-events returns qr_url field
// Find the endpoint and ensure it includes:
// =====================================================

/**
 * Example modification for the big-events endpoint:
 * 
 * app.get('/api/big-events', async (req, res) => {
 *   try {
 *     const result = await pool.query(`
 *       SELECT 
 *         id,
 *         title,
 *         description,
 *         start_at,
 *         fee,
 *         qr_url,
 *         qr_payment_method,
 *         ... other fields ...
 *       FROM events
 *       WHERE type = 'BIG_EVENT' AND visibility = 'public'
 *       ORDER BY start_at DESC
 *     `);
 *     return res.json(result.rows);
 *   } catch (err) {
 *     return res.status(500).json({ message: 'Server error' });
 *   }
 * });
 */

// ====================================
// LOCATION 6: Error handling for multer
// =====================================================
// Add this before app.listen() for better error handling
// =====================================================

app.use((err, req, res, next) => {
  if (err instanceof multer.MulterError) {
    console.error('Multer Error:', err);
    return res.status(400).json({ message: `File upload error: ${err.message}` });
  } else if (err) {
    console.error('Upload Error:', err);
    return res.status(400).json({ message: err.message || 'Upload failed' });
  }
  next();
});

