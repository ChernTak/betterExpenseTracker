// Remote kill-switch for voice logging (FR4.4); env-var-backed since it's just one boolean with no admin UI need yet.
function getFeatureFlags(req, res) {
  return res.status(200).json({
    voiceHandsFreeEnabled: process.env.VOICE_HANDS_FREE_ENABLED !== 'false',
  });
}

module.exports = { getFeatureFlags };
