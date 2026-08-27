// Remote kill-switch for client features that can misbehave post-release
// without a way to disable them short of an app update — currently just
// FR4.4 voice logging. Env-var-backed rather than a DB table since it's a
// single boolean nobody needs to edit through an admin UI yet; add a table
// if that changes.
function getFeatureFlags(req, res) {
  return res.status(200).json({
    voiceHandsFreeEnabled: process.env.VOICE_HANDS_FREE_ENABLED !== 'false',
  });
}

module.exports = { getFeatureFlags };
