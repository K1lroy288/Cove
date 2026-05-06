-- idx_friendships_status бесполезен (3 значения, кардинальность низкая)
DROP INDEX IF EXISTS idx_friendships_status;

-- GetPendingRequests: WHERE friend_id=? AND status='pending'
CREATE INDEX IF NOT EXISTS idx_friendships_friend_status ON friendships(friend_id, status);

-- GetFriends: WHERE user_id=? AND status='accepted'
CREATE INDEX IF NOT EXISTS idx_friendships_user_status ON friendships(user_id, status);
