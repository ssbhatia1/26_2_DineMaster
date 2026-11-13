package com.dinemaster.auth.dto;

import jakarta.validation.constraints.NotNull;

public record ActivationCodeCreateRequest(@NotNull Long branchId) { }
