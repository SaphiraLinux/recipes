bind_socket = "127.0.0.1:11332";
upstream "local" {
  default = true;
  self_scan = false;
}
