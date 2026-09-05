# mailDragon seed overrides; full metrics/controllers workers are added by
# deployment config.
worker "normal" {
	bind_socket = "localhost:11333 {
		milter = yes;
	}";
}
