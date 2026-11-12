-- Older V9 installations may contain cross-branch grants. Keep those rows for
-- review, but require a deliberate staff branch assignment before honoring them.
ALTER TABLE user_branches
    ADD COLUMN assignment_verified BOOLEAN NOT NULL DEFAULT FALSE;
