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

const goalRoutes = require('./src/routes/goal.routes');
app.use('/api/goals', goalRoutes);

const wishlistRoutes = require('./src/routes/wishlist.routes');
app.use('/api/wishlist', wishlistRoutes);

const adminRoutes = require('./src/routes/admin.routes');
app.use('/api/admin', adminRoutes);

const recommendationRoutes = require('./src/routes/recommendation.routes');
app.use('/api/recommendations', recommendationRoutes);

const configRoutes = require('./src/routes/config.routes');
app.use('/api/config', configRoutes);

const nudgeRoutes = require('./src/routes/nudge.routes');
app.use('/api/nudge', nudgeRoutes);

// True only when run directly (`node app.js`), not when supertest `require`s it — so `npm test` skips binding a real port and the embedding warm-up.
if (require.main === module) {
  const PORT = process.env.PORT || 3000;
  app.listen(PORT, () => {
    console.log(`Server is running on port ${PORT}...`);
  });

  // Warm up the embedding model/category embeddings in background so the first categorize call isn't the one paying for the download/load.
  const embeddingService = require('./src/services/embedding.service');
  embeddingService
    .preload()
    .then(() => console.log('Category embedding model ready'))
    .catch((err) => console.error('Failed to preload embedding model', err));
}

module.exports = app;