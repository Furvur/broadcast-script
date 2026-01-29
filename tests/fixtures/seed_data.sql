-- Create tables mimicking Broadcast schema
CREATE TABLE broadcast_channels (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE subscribers (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL,
    broadcast_channel_id INTEGER REFERENCES broadcast_channels(id),
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE broadcasts (
    id SERIAL PRIMARY KEY,
    subject VARCHAR(255) NOT NULL,
    broadcast_channel_id INTEGER REFERENCES broadcast_channels(id),
    created_at TIMESTAMP DEFAULT NOW()
);

-- Seed test data
INSERT INTO broadcast_channels (name) VALUES
    ('Test Channel 1'),
    ('Test Channel 2'),
    ('Test Channel 3');

INSERT INTO subscribers (email, broadcast_channel_id) VALUES
    ('user1@test.com', 1),
    ('user2@test.com', 1),
    ('user3@test.com', 2),
    ('user4@test.com', 2),
    ('user5@test.com', 3);

INSERT INTO broadcasts (subject, broadcast_channel_id) VALUES
    ('Welcome Email', 1),
    ('Newsletter #1', 1),
    ('Promo Email', 2);
