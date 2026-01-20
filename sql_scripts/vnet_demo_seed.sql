IF OBJECT_ID('dbo.demo_customers','U') IS NULL
BEGIN
CREATE TABLE dbo.demo_customers (
    customer_id INT IDENTITY(1,1) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    segment VARCHAR(32) NOT NULL,
    last_update DATETIME2 NOT NULL
);
END

IF NOT EXISTS (SELECT 1 FROM dbo.demo_customers)
BEGIN
INSERT INTO dbo.demo_customers (name, segment, last_update) VALUES ('Ada Lovelace', 'Analytics', '2026-01-20T08:00:00Z');
INSERT INTO dbo.demo_customers (name, segment, last_update) VALUES ('Alan Turing', 'Engineering', '2026-01-20T08:05:00Z');
INSERT INTO dbo.demo_customers (name, segment, last_update) VALUES ('Katherine Johnson', 'Operations', '2026-01-20T08:10:00Z');
INSERT INTO dbo.demo_customers (name, segment, last_update) VALUES ('Grace Hopper', 'Platform', '2026-01-20T08:15:00Z');
INSERT INTO dbo.demo_customers (name, segment, last_update) VALUES ('Mary Jackson', 'Research', '2026-01-20T08:20:00Z');
END

IF OBJECT_ID('dbo.NetworkChecks','U') IS NULL
BEGIN
CREATE TABLE dbo.NetworkChecks (
    check_id INT IDENTITY(1,1) PRIMARY KEY,
    component VARCHAR(50) NOT NULL,
    status VARCHAR(12) NOT NULL,
    checked_at DATETIME2 NOT NULL
);
END

IF NOT EXISTS (SELECT 1 FROM dbo.NetworkChecks)
BEGIN
INSERT INTO dbo.NetworkChecks (component, status, checked_at) VALUES ('web-tier', 'OK', '2026-01-20T08:00:00Z');
INSERT INTO dbo.NetworkChecks (component, status, checked_at) VALUES ('app-tier', 'OK', '2026-01-20T08:05:00Z');
INSERT INTO dbo.NetworkChecks (component, status, checked_at) VALUES ('db-tier', 'OK', '2026-01-20T08:10:00Z');
INSERT INTO dbo.NetworkChecks (component, status, checked_at) VALUES ('private-endpoint', 'OK', '2026-01-20T08:15:00Z');
INSERT INTO dbo.NetworkChecks (component, status, checked_at) VALUES ('dns-zone', 'OK', '2026-01-20T08:20:00Z');
END
