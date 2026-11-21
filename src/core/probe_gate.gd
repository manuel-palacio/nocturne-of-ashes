class_name ProbeGate
extends RefCounted
## Whether the page may use the browser tests' probe and the test parameters that go with it (see
## `Probe` and `PageBoot`): with `probe=1` in the page URL, and never in the public build, the one the
## site serves, which is exported with the `public` feature (the "Web public" export preset). The page
## has parameters only on the web (`PageParams`), so off the web the probe is never allowed.

## The custom feature the public build is exported with.
const PUBLIC_FEATURE: String = "public"


## Whether `params`, the page's parameters by name, turn the probe on in a build whose features
## `has_feature` answers for (by default this build's own, `OS.has_feature()`).
static func allows(
		params: Dictionary = PageParams.all(), has_feature: Callable = Callable(OS, "has_feature")
) -> bool:
	return params.get("probe") == "1" and not has_feature.call(PUBLIC_FEATURE)
