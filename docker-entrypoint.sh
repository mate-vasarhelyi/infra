#!/bin/bash
code-server --bind-addr 0.0.0.0:8080 --auth none &
exec ttyd -p 7681 -W zellij
