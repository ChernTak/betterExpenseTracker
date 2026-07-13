require('dotenv').config();

const express = require('express');
const app = express();

app.use(express.json());

//Import and mount project routes
const authRoutes = require('./src/routes/auth.routes');
app.use('/api/auth', authRoutes);

const expenseRoutes = require('./src/routes/expense.routes');
app.use('/api/expenses', expenseRoutes);

const budgetRoutes = require('./src/routes/budget.routes');
app.use('/api/budgets', budgetRoutes);

const ocrRoutes = require('./src/routes/ocr.routes');
app.use('/api/ocr', ocrRoutes);

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Server is running on port ${PORT}...`);
});

// Warm up the embedding model and category embeddings in the background so
// the first /api/expenses/categorize call that needs the embedding fallback
// isn't the one paying for the model download/load.
const embeddingService = require('./src/services/embedding.service');
embeddingService
  .preload()
  .then(() => console.log('Category embedding model ready'))
  .catch((err) => console.error('Failed to preload embedding model', err));