package com.dinemaster.user.repository;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import java.util.List;

@Repository
public class UserBranchRepository {
    private final JdbcTemplate jdbc;
    public UserBranchRepository(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    public List<Long> findBranchIds(Long userId) {
        return jdbc.query("select branch_id from user_branches where user_id = ? order by branch_id",
                (rs, row) -> rs.getLong(1), userId);
    }

    public boolean isAssigned(Long userId, Long branchId) {
        Integer count = jdbc.queryForObject(
                "select count(*) from user_branches where user_id = ? and branch_id = ?",
                Integer.class, userId, branchId);
        return count != null && count > 0;
    }

    public void replaceBranches(Long userId, List<Long> branchIds) {
        jdbc.update("delete from user_branches where user_id = ?", userId);
        branchIds.stream().distinct().forEach(branchId ->
                jdbc.update("insert into user_branches (user_id, branch_id) values (?, ?)", userId, branchId));
    }
}
