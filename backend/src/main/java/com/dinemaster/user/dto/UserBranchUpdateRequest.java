package com.dinemaster.user.dto;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import java.util.List;

public record UserBranchUpdateRequest(@NotNull List<@Positive Long> branchIds) { }
