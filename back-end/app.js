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

const categoryRoutes = require('./src/routes/category.routes');
app.use('/api/categories', categoryRoutes);

const insightRoutes = require('./src/routes/insight.routes');
app.use('/api/insights', insightRoutes);

const incomeRoutes = require('./src/routes/income.routes');
app.use('/api/income', incomeRoutes);

const adminRoutes = require('./src/routes/admin.routes');
app.use('/api/admin', adminRoutes);

const recommendationRoutes = require('./src/routes/recommendation.routes');
app.use('/api/recommendations', recommendationRoutes);

// `require.main === module` is only true when this file is run directly
// (`node app.js`), not when the test suite `require`s it via supertest —
// so `npm test` gets the same routed app without also binding a real port
// or paying for the (network-downloaded) embedding model warm-up.
if (require.main === module) {
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
}

module.exports = app;