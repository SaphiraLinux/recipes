// Copyright 2026 The Kubernetes Authors (thin Saphira wrapper).
// SPDX-License-Identifier: Apache-2.0
//
// Saphira's kubectl entrypoint. Upstream ships the kubectl BINARY from the
// monorepo (k8s.io/kubernetes/staging/src/k8s.io/kubectl/cmd/kubectl),
// whose main is exactly this shape: build the default command from the
// k8s.io/kubectl library and execute it. We build the same binary from the
// standalone k8s.io/kubectl module instead of vendoring the ~150MB
// monorepo, so this 1:1-equivalent main lives in the recipe.
package main

import (
	"os"

	"k8s.io/kubectl/pkg/cmd"
	"k8s.io/kubectl/pkg/cmd/util"
)

func main() {
	c := cmd.NewDefaultKubectlCommand()
	if err := c.Execute(); err != nil {
		util.CheckErr(err)
		os.Exit(1)
	}
}
