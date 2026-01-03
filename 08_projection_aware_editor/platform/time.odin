package platform

import stime "shared:sokol/time"

time_setup :: proc() {
	stime.setup()
}

time_now :: proc() -> u64 {
	return stime.now()
}

time_delta_since :: proc(last: u64) -> u64 {
	return stime.diff(stime.now(), last)
}
