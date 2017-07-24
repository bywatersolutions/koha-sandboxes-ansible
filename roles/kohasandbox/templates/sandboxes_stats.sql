CREATE TABLE IF NOT EXISTS stats (
    id       INT auto_increment,
    instance VARCHAR(30),
    name     TEXT,
    email    VARCHAR(255),
    date     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    action   VARCHAR(255) NOT NULL,
    bznumber VARCHAR(255) NOT NULL,
    host     VARCHAR(255),
    PRIMARY KEY (id)
);
