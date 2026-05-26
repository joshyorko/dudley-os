package main

import (
	"context"
	"strings"
	"time"

	"dagger/dudley-os/internal/dagger"
)

type DudleyOs struct {
	Source *dagger.Directory
}

func New(
	// +defaultPath="/"
	// +ignore=[".codex", "output", "*_build*"]
	source *dagger.Directory,
) *DudleyOs {
	return &DudleyOs{Source: source}
}

// Return the portable release metadata and tag plan.
func (m *DudleyOs) Metadata(
	ctx context.Context,
	// Registry namespace, for example ghcr.io/joshyorko or localhost:5000.
	// +optional
	registry string,
	// Image name to build and publish.
	// +optional
	imageName string,
	// Stable/default image tag.
	// +optional
	stableTag string,
	// GitHub-style repository owner used in OCI labels.
	// +optional
	owner string,
	// Commit SHA. Defaults to git rev-parse HEAD inside the source tree.
	// +optional
	sha string,
	// Source ref name for provenance.
	// +optional
	refName string,
	// Pipeline URL for provenance.
	// +optional
	pipelineURL string,
	// Source repository URI for provenance.
	// +optional
	sourceURI string,
) (*ReleasePlan, error) {
	resolvedSHA, err := m.resolveSHA(ctx, sha)
	if err != nil {
		return nil, err
	}

	plan := planRelease(releasePlanInput{
		Registry:    registry,
		ImageName:   imageName,
		StableTag:   stableTag,
		Owner:       owner,
		SHA:         resolvedSHA,
		RefName:     refName,
		PipelineURL: pipelineURL,
		SourceURI:   sourceURI,
		Now:         time.Now().UTC(),
	})

	return plan, nil
}

// Build the bootc image with Buildah without publishing.
func (m *DudleyOs) Build(
	ctx context.Context,
	// Registry namespace, for example ghcr.io/joshyorko or localhost:5000.
	// +optional
	registry string,
	// Image name to build.
	// +optional
	imageName string,
	// Stable/default image tag.
	// +optional
	stableTag string,
	// GitHub-style repository owner used in OCI labels.
	// +optional
	owner string,
	// Commit SHA used in OCI labels.
	// +optional
	sha string,
	// Buildah runner image.
	// +optional
	buildahImage string,
) (string, error) {
	plan, err := m.Metadata(ctx, registry, imageName, stableTag, owner, sha, "", "", "")
	if err != nil {
		return "", err
	}

	return m.buildah(plan, buildahImage, false, false, "", nil).Stdout(ctx)
}

// Build with Buildah and push every generated tag.
func (m *DudleyOs) Publish(
	ctx context.Context,
	// Registry namespace, for example ghcr.io/joshyorko or localhost:5000.
	// +optional
	registry string,
	// Image name to publish.
	// +optional
	imageName string,
	// Stable/default image tag.
	// +optional
	stableTag string,
	// GitHub-style repository owner used in OCI labels.
	// +optional
	owner string,
	// Commit SHA.
	// +optional
	sha string,
	// Registry username. Not needed for open local registries.
	// +optional
	registryUsername string,
	// Registry password/token. Not needed for open local registries.
	// +optional
	registryPassword *dagger.Secret,
	// Buildah runner image.
	// +optional
	buildahImage string,
) (*ReleaseSummary, error) {
	plan, err := m.Metadata(ctx, registry, imageName, stableTag, owner, sha, "", "", "")
	if err != nil {
		return nil, err
	}

	container := m.buildah(plan, buildahImage, true, false, registryUsername, registryPassword)
	digestRefs, err := digestRefs(ctx, container)
	if err != nil {
		return nil, err
	}
	log, err := container.Stdout(ctx)
	if err != nil {
		return nil, err
	}

	summary := summaryFromPlan(plan)
	summary.Published = true
	summary.DigestRefs = digestRefs
	summary.BuildLog = log
	return summary, nil
}

// Generate a Trivy SPDX JSON SBOM for the built image.
func (m *DudleyOs) Sbom(
	ctx context.Context,
	// Registry namespace, for example ghcr.io/joshyorko or localhost:5000.
	// +optional
	registry string,
	// Image name to build.
	// +optional
	imageName string,
	// Stable/default image tag.
	// +optional
	stableTag string,
	// GitHub-style repository owner used in OCI labels.
	// +optional
	owner string,
	// Commit SHA.
	// +optional
	sha string,
	// Buildah runner image.
	// +optional
	buildahImage string,
	// Trivy image.
	// +optional
	trivyImage string,
) (*dagger.File, error) {
	plan, err := m.Metadata(ctx, registry, imageName, stableTag, owner, sha, "", "", "")
	if err != nil {
		return nil, err
	}

	build := m.buildah(plan, buildahImage, false, true, "", nil)
	return m.sbomFromArchive(plan, build.File("/out/image.tar"), trivyImage), nil
}

// Sign an image ref with cosign and a key secret.
func (m *DudleyOs) Sign(
	ctx context.Context,
	// Image digest ref to sign.
	imageRef string,
	// Registry username. Not needed for open local registries.
	// +optional
	registryUsername string,
	// Registry password/token. Not needed for open local registries.
	// +optional
	registryPassword *dagger.Secret,
	// Cosign private key.
	signingKey *dagger.Secret,
	// Cosign private key password. Use an empty secret for unencrypted keys.
	// +optional
	signingPassword *dagger.Secret,
	// Cosign image.
	// +optional
	cosignImage string,
) (string, error) {
	return cosignSign(imageRef, registryUsername, registryPassword, signingKey, signingPassword, cosignImage).Stdout(ctx)
}

// Attach an SPDX JSON SBOM attestation to an image ref.
func (m *DudleyOs) AttestSbom(
	ctx context.Context,
	// Image digest ref to attest.
	imageRef string,
	// SPDX JSON SBOM file.
	sbom *dagger.File,
	// Registry username. Not needed for open local registries.
	// +optional
	registryUsername string,
	// Registry password/token. Not needed for open local registries.
	// +optional
	registryPassword *dagger.Secret,
	// Cosign private key.
	signingKey *dagger.Secret,
	// Cosign private key password. Use an empty secret for unencrypted keys.
	// +optional
	signingPassword *dagger.Secret,
	// Cosign image.
	// +optional
	cosignImage string,
) (string, error) {
	return cosignAttestFile(imageRef, "spdxjson", sbom, registryUsername, registryPassword, signingKey, signingPassword, cosignImage).Stdout(ctx)
}

// Attach a SLSA provenance attestation to an image ref.
func (m *DudleyOs) AttestProvenance(
	ctx context.Context,
	// Image digest ref to attest.
	imageRef string,
	// Registry username. Not needed for open local registries.
	// +optional
	registryUsername string,
	// Registry password/token. Not needed for open local registries.
	// +optional
	registryPassword *dagger.Secret,
	// Commit SHA. Defaults to git rev-parse HEAD inside the source tree.
	// +optional
	sha string,
	// Source ref name for provenance.
	// +optional
	refName string,
	// Pipeline URL for provenance.
	// +optional
	pipelineURL string,
	// Source repository URI for provenance.
	// +optional
	sourceURI string,
	// Cosign private key.
	signingKey *dagger.Secret,
	// Cosign private key password. Use an empty secret for unencrypted keys.
	// +optional
	signingPassword *dagger.Secret,
	// Cosign image.
	// +optional
	cosignImage string,
) (string, error) {
	registry, imageName := repositoryParts(imageRef)
	plan, err := m.Metadata(ctx, registry, imageName, "", "", sha, refName, pipelineURL, sourceURI)
	if err != nil {
		return "", err
	}
	file, err := provenanceFile(plan)
	if err != nil {
		return "", err
	}
	return cosignAttestFile(imageRef, "slsaprovenance", file, registryUsername, registryPassword, signingKey, signingPassword, cosignImage).Stdout(ctx)
}

// Run the full release pipeline. With publish=false this is a dry-run planner.
func (m *DudleyOs) Release(
	ctx context.Context,
	// Registry namespace, for example ghcr.io/joshyorko or localhost:5000.
	// +optional
	registry string,
	// Image name to build and publish.
	// +optional
	imageName string,
	// Registry username. Not needed for open local registries.
	// +optional
	registryUsername string,
	// Registry password/token. Not needed for open local registries.
	// +optional
	registryPassword *dagger.Secret,
	// Cosign private key. Signing and attestations are skipped when absent.
	// +optional
	signingKey *dagger.Secret,
	// Cosign private key password. Use an empty secret for unencrypted keys.
	// +optional
	signingPassword *dagger.Secret,
	// Commit SHA. Defaults to git rev-parse HEAD inside the source tree.
	// +optional
	sha string,
	// Source ref name for provenance.
	// +optional
	refName string,
	// Pipeline URL for provenance.
	// +optional
	pipelineURL string,
	// Source repository URI for provenance.
	// +optional
	sourceURI string,
	// Publish images and produce release supply-chain material.
	// +default=true
	publish bool,
	// Sign published digest refs when signing-key is provided.
	// +default=true
	sign bool,
	// Attach SBOM and SLSA provenance attestations when signing-key is provided.
	// +default=true
	attest bool,
	// Stable/default image tag.
	// +optional
	stableTag string,
	// GitHub-style repository owner used in OCI labels.
	// +optional
	owner string,
	// Buildah runner image.
	// +optional
	buildahImage string,
	// Trivy image.
	// +optional
	trivyImage string,
	// Cosign image.
	// +optional
	cosignImage string,
) (*ReleaseSummary, error) {
	plan, err := m.Metadata(ctx, registry, imageName, stableTag, owner, sha, refName, pipelineURL, sourceURI)
	if err != nil {
		return nil, err
	}

	summary := summaryFromPlan(plan)
	if !publish {
		summary.PublishSkippedReason = "publish=false"
		summary.SBOMSkippedReason = "publish=false"
		summary.SignSkippedReason = "publish=false"
		summary.AttestSkippedReason = "publish=false"
		return summary, nil
	}

	build := m.buildah(plan, buildahImage, true, true, registryUsername, registryPassword)
	digestRefs, err := digestRefs(ctx, build)
	if err != nil {
		return nil, err
	}
	log, err := build.Stdout(ctx)
	if err != nil {
		return nil, err
	}

	summary.Published = true
	summary.DigestRefs = digestRefs
	summary.BuildLog = log

	sbom := m.sbomFromArchive(plan, build.File("/out/image.tar"), trivyImage)
	if _, err := sbom.Contents(ctx); err != nil {
		return nil, err
	}
	summary.SBOMGenerated = true

	if signingKey == nil {
		summary.SignSkippedReason = "signing-key not provided"
		summary.AttestSkippedReason = "signing-key not provided"
		return summary, nil
	}
	if !sign {
		summary.SignSkippedReason = "sign=false"
	} else {
		for _, ref := range uniqueDigestRefs(digestRefs) {
			if _, err := cosignSign(ref, registryUsername, registryPassword, signingKey, signingPassword, cosignImage).Stdout(ctx); err != nil {
				return nil, err
			}
		}
		summary.Signed = true
	}

	if !attest {
		summary.AttestSkippedReason = "attest=false"
		return summary, nil
	}

	prov, err := provenanceFile(plan)
	if err != nil {
		return nil, err
	}
	for _, ref := range uniqueDigestRefs(digestRefs) {
		if _, err := cosignAttestFile(ref, "spdxjson", sbom, registryUsername, registryPassword, signingKey, signingPassword, cosignImage).Stdout(ctx); err != nil {
			return nil, err
		}
		if _, err := cosignAttestFile(ref, "slsaprovenance", prov, registryUsername, registryPassword, signingKey, signingPassword, cosignImage).Stdout(ctx); err != nil {
			return nil, err
		}
	}
	summary.Attested = true

	return summary, nil
}

func (m *DudleyOs) resolveSHA(ctx context.Context, sha string) (string, error) {
	if strings.TrimSpace(sha) != "" {
		return strings.TrimSpace(sha), nil
	}
	out, err := m.git("rev-parse", "HEAD").Stdout(ctx)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(out), nil
}

func (m *DudleyOs) git(args ...string) *dagger.Container {
	return dag.Container().
		From("alpine/git:latest").
		WithMountedDirectory("/src", m.Source).
		WithWorkdir("/src").
		WithExec(append([]string{"git"}, args...))
}
