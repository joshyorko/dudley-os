package main

import (
	"context"
	"fmt"
	"strings"

	"dagger/dudley-os/internal/dagger"
)

func (m *DudleyOs) buildah(
	plan *ReleasePlan,
	buildahImage string,
	publish bool,
	archive bool,
	registryUsername string,
	registryPassword *dagger.Secret,
) *dagger.Container {
	buildahImage = defaultString(buildahImage, defaultBuildahImage)
	localRef := fmt.Sprintf("%s:%s", defaultImageName, plan.Tags[0])

	args := []string{
		"buildah", "bud",
		"--pull=newer",
		"--format=docker",
		"--tag", localRef,
		"--build-arg", "SHA_HEAD_SHORT=" + plan.BuildSHA,
		"--build-arg", "FINAL_IMAGE_REF=" + plan.PrimaryRef,
		"--build-arg", "VSCODE_REFRESH_TOKEN=" + strings.NewReplacer("-", "", ":", "", "T", "", "Z", "").Replace(plan.Created),
	}
	for _, label := range plan.Labels {
		args = append(args, "--label", label)
	}
	args = append(args, "--file", "Containerfile", ".")

	lines := []string{
		"set -euo pipefail",
		"mkdir -p /out/digests",
		"buildah version",
		shellQuote(args),
	}

	for _, tag := range plan.Tags {
		lines = append(lines, fmt.Sprintf("buildah tag %s %s", shellWord(localRef), shellWord(fmt.Sprintf("%s:%s", plan.Image, tag))))
	}

	if archive {
		lines = append(lines, "buildah push "+shellWord(localRef)+" "+shellWord(fmt.Sprintf("docker-archive:/out/image.tar:%s", localRef)))
	}

	if publish {
		if registryUsername != "" && registryPassword != nil {
			lines = append(lines, "printf '%s' \"$REGISTRY_PASSWORD\" | buildah login "+plan.TLSVerifyArg+" --username \"$REGISTRY_USERNAME\" --password-stdin "+shellWord(registryHost(plan.Image)))
		}
		lines = append(lines, "> /out/digest-refs.txt")
		for _, tag := range plan.Tags {
			ref := fmt.Sprintf("%s:%s", plan.Image, tag)
			digestPath := fmt.Sprintf("/out/digests/%s.digest", sanitizeFilePart(tag))
			lines = append(lines, "buildah push "+plan.TLSVerifyArg+" --digestfile "+shellWord(digestPath)+" --compression-format=zstd:chunked "+shellWord(ref))
			lines = append(lines, "printf '%s@%s\\n' "+shellWord(plan.Image)+" \"$(cat "+shellWord(digestPath)+")\" >> /out/digest-refs.txt")
		}
	}

	lines = append(lines, "buildah images")

	container := dag.Container().
		From(buildahImage).
		WithMountedDirectory("/src", m.Source).
		WithWorkdir("/src").
		WithMountedCache("/var/lib/containers", dag.CacheVolume("dudley-os-buildah-containers")).
		WithEnvVariable("STORAGE_DRIVER", "vfs")

	if registryUsername != "" {
		container = container.WithEnvVariable("REGISTRY_USERNAME", registryUsername)
	}
	if registryPassword != nil {
		container = container.WithSecretVariable("REGISTRY_PASSWORD", registryPassword)
	}

	return container.WithExec([]string{"bash", "-lc", strings.Join(lines, "\n")}, dagger.ContainerWithExecOpts{
		InsecureRootCapabilities: true,
	})
}

func digestRefs(ctx context.Context, container *dagger.Container) ([]string, error) {
	contents, err := container.File("/out/digest-refs.txt").Contents(ctx)
	if err != nil {
		return nil, err
	}
	var refs []string
	for _, line := range strings.Split(contents, "\n") {
		line = strings.TrimSpace(line)
		if line != "" {
			refs = append(refs, line)
		}
	}
	return refs, nil
}

func shellQuote(args []string) string {
	quoted := make([]string, 0, len(args))
	for _, arg := range args {
		quoted = append(quoted, shellWord(arg))
	}
	return strings.Join(quoted, " ")
}

func shellWord(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "'\\''") + "'"
}

func sanitizeFilePart(value string) string {
	value = strings.ReplaceAll(value, "/", "_")
	value = strings.ReplaceAll(value, ":", "_")
	return value
}
