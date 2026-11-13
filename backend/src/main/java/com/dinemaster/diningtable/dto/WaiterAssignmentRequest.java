package com.dinemaster.diningtable.dto;

import jakarta.validation.constraints.Positive;

public record WaiterAssignmentRequest(@Positive Long waiterId) { }
