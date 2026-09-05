const db = require('../config/db');

exports.createGoal = ({ userId, goalName, targetAmount, deadlineDate, priority, icon, notes }) => {
  const query = `
    INSERT INTO saving_goals (user_id, goal_name, target_amount, deadline_date, priority, icon, notes)
    VALUES ($1, $2, $3, $4, COALESCE($5, 1), $6, $7)
    RETURNING *
  `;
  return db.query(query, [
    userId,
    goalName,
    targetAmount,
    deadlineDate || null,
    priority ?? null,
    icon || null,
    notes || null,
  ]);
};

exports.listGoalsForUser = (userId) => {
  const query = `
    SELECT * FROM saving_goals
    WHERE user_id = $1
    ORDER BY status = 'active' DESC, priority DESC, created_at DESC
  `;
  return db.query(query, [userId]);
};

exports.getGoalForUser = (goalId, userId) => {
  return db.query('SELECT * FROM saving_goals WHERE goal_id = $1 AND user_id = $2', [goalId, userId]);
};

exports.updateGoal = (goalId, userId, { goalName, targetAmount, deadlineDate, status, priority, icon, notes }) => {
  const query = `
    UPDATE saving_goals
    SET goal_name = COALESCE($1, goal_name),
        target_amount = COALESCE($2, target_amount),
        deadline_date = COALESCE($3, deadline_date),
        status = COALESCE($4, status),
        priority = COALESCE($5, priority),
        icon = COALESCE($6, icon),
        notes = COALESCE($7, notes),
        updated_at = NOW()
    WHERE goal_id = $8 AND user_id = $9
    RETURNING *
  `;
  return db.query(query, [
    goalName ?? null,
    targetAmount ?? null,
    deadlineDate ?? null,
    status ?? null,
    priority ?? null,
    icon ?? null,
    notes ?? null,
    goalId,
    userId,
  ]);
};

exports.deleteGoal = (goalId, userId) => {
  return db.query('DELETE FROM saving_goals WHERE goal_id = $1 AND user_id = $2', [goalId, userId]);
};

exports.listContributions = (goalId, userId) => {
  const query = `
    SELECT c.* FROM saving_goal_contributions c
    JOIN saving_goals g ON g.goal_id = c.goal_id
    WHERE c.goal_id = $1 AND g.user_id = $2
    ORDER BY c.contributed_at DESC
  `;
  return db.query(query, [goalId, userId]);
};

// Feeds "Available to spend" so money already committed to goals this month isn't shown as spendable.
exports.getContributionsTotalForMonth = (userId, monthStart, monthEndExclusive) => {
  const query = `
    SELECT COALESCE(SUM(amount), 0) AS total
    FROM saving_goal_contributions
    WHERE user_id = $1 AND contributed_at >= $2 AND contributed_at < $3
  `;
  return db.query(query, [userId, monthStart, monthEndExclusive]);
};

// Inserts the contribution and bumps current_saved in one transaction, auto-completing the goal once it reaches target_amount.
exports.addContribution = async (goalId, userId, { amount, note }) => {
  const client = await db.connect();
  try {
    await client.query('BEGIN');

    const goalResult = await client.query(
      'SELECT * FROM saving_goals WHERE goal_id = $1 AND user_id = $2 FOR UPDATE',
      [goalId, userId],
    );
    const goal = goalResult.rows[0];
    if (!goal) {
      await client.query('ROLLBACK');
      return null;
    }

    const contributionResult = await client.query(
      `INSERT INTO saving_goal_contributions (goal_id, user_id, amount, note)
       VALUES ($1, $2, $3, $4)
       RETURNING *`,
      [goalId, userId, amount, note || null],
    );

    const newSaved = Number(goal.current_saved) + Number(amount);
    const newStatus = newSaved >= Number(goal.target_amount) ? 'completed' : goal.status;

    const updatedGoalResult = await client.query(
      `UPDATE saving_goals
       SET current_saved = $1, status = $2, updated_at = NOW()
       WHERE goal_id = $3
       RETURNING *`,
      [newSaved, newStatus, goalId],
    );

    await client.query('COMMIT');
    return { contribution: contributionResult.rows[0], goal: updatedGoalResult.rows[0] };
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
};
