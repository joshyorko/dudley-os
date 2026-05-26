package main

import (
	"strings"

	"dagger/dudley-os/internal/dagger"
)

func (m *DudleyOs) sbomFromArchive(plan *ReleasePlan, archive *dagger.File, trivyImage string) *dagger.File {
	trivyImage = defaultString(trivyImage, defaultTrivyImage)
	return dag.Container().
		From(trivyImage).
		WithMountedCache("/root/.cache/trivy", dag.CacheVolume("dudley-os-trivy-cache")).
		WithFile("/work/image.tar", archive).
		WithExec([]string{
			"trivy", "image",
			"--input", "/work/image.tar",
			"--format", "spdx-json",
			"--output", "/work/" + plan.SBOMName,
			"--offline-scan",
			"--skip-db-update",
			"--skip-java-db-update",
		}).
		File("/work/" + plan.SBOMName)
}

func provenanceFile(plan *ReleasePlan) (*dagger.File, error) {
	predicate, err := provenancePredicate(plan)
	if err != nil {
		return nil, err
	}
	return dag.Container().
		From("alpine:latest").
		WithNewFile("/work/"+plan.ProvenanceName, string(predicate)).
		File("/work/" + plan.ProvenanceName), nil
}

func cosignSign(imageRef string, registryUsername string, registryPassword *dagger.Secret, signingKey *dagger.Secret, signingPassword *dagger.Secret, cosignImage string) *dagger.Container {
	args := []string{"sign", "-y", "--key", "env://COSIGN_PRIVATE_KEY", "--tlog-upload=false"}
	if !tlsVerify(imageRef) {
		args = append(args, "--allow-insecure-registry")
	}
	args = append(args, imageRef)

	return cosignBase(imageRef, registryUsername, registryPassword, signingKey, signingPassword, cosignImage).WithExec([]string{"sh", "-lc", cosignScript(args)})
}

func cosignAttestFile(imageRef string, predicateType string, predicate *dagger.File, registryUsername string, registryPassword *dagger.Secret, signingKey *dagger.Secret, signingPassword *dagger.Secret, cosignImage string) *dagger.Container {
	args := []string{
		"attest", "-y",
		"--key", "env://COSIGN_PRIVATE_KEY",
		"--tlog-upload=false",
		"--type", predicateType,
		"--predicate", "/work/predicate.json",
	}
	if !tlsVerify(imageRef) {
		args = append(args, "--allow-insecure-registry")
	}
	args = append(args, imageRef)

	return cosignBase(imageRef, registryUsername, registryPassword, signingKey, signingPassword, cosignImage).
		WithFile("/work/predicate.json", predicate).
		WithExec([]string{"sh", "-lc", cosignScript(args)})
}

func cosignBase(imageRef string, registryUsername string, registryPassword *dagger.Secret, signingKey *dagger.Secret, signingPassword *dagger.Secret, cosignImage string) *dagger.Container {
	cosignImage = defaultString(cosignImage, defaultCosignImage)
	container := dag.Container().
		From("alpine:latest").
		WithFile("/usr/local/bin/cosign", dag.Container().From(cosignImage).File("/ko-app/cosign"), dagger.ContainerWithFileOpts{Permissions: 0755}).
		WithEnvVariable("COSIGN_EXPERIMENTAL", "false").
		WithSecretVariable("COSIGN_PRIVATE_KEY", signingKey)

	if registryUsername != "" {
		container = container.WithEnvVariable("REGISTRY_USERNAME", registryUsername)
	}
	if registryPassword != nil {
		container = container.WithSecretVariable("REGISTRY_PASSWORD", registryPassword)
	}
	if signingPassword != nil {
		container = container.WithSecretVariable("COSIGN_PASSWORD", signingPassword)
	}

	return container.WithEnvVariable("REGISTRY_HOST", registryHost(imageRepository(imageRef)))
}

func cosignScript(args []string) string {
	lines := []string{"set -eu"}
	lines = append(lines, "if [ -n \"${REGISTRY_USERNAME:-}\" ] && [ -n \"${REGISTRY_PASSWORD:-}\" ]; then mkdir -p \"$HOME/.docker\"; auth=\"$(printf '%s:%s' \"$REGISTRY_USERNAME\" \"$REGISTRY_PASSWORD\" | base64 | tr -d '\\n')\"; printf '{\"auths\":{\"%s\":{\"auth\":\"%s\"}}}\\n' \"$REGISTRY_HOST\" \"$auth\" > \"$HOME/.docker/config.json\"; fi")
	lines = append(lines, "exec /usr/local/bin/cosign "+shellQuote(args))
	return strings.Join(lines, "\n")
}

func uniqueDigestRefs(refs []string) []string {
	seen := map[string]bool{}
	var out []string
	for _, ref := range refs {
		digest := ref
		if _, after, ok := strings.Cut(ref, "@"); ok {
			digest = after
		}
		if seen[digest] {
			continue
		}
		seen[digest] = true
		out = append(out, ref)
	}
	return out
}
