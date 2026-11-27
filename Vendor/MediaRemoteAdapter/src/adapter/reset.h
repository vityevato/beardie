// Copyright (c) 2026 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#ifndef MEDIAREMOTEADAPTER_ADAPTER_RESET_H
#define MEDIAREMOTEADAPTER_ADAPTER_RESET_H

// Clears a stale now playing application election override. A fresh process
// cannot clear the override by disabling it directly, because MediaRemote
// skips a value equal to the last value this process set. Enabling and then
// disabling the override forces both calls through.
void adapter_reset(void);

#endif // MEDIAREMOTEADAPTER_ADAPTER_RESET_H
