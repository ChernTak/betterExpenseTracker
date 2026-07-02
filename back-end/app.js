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