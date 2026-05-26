package main

import (
	"encoding/json"
	"fmt"
	"strings"
	"time"
)

const (
	defaultImageName    = "dudley-os"
	defaultRegistry     = "ghcr.io/joshyorko"
	defaultStableTag    = "stable"
	defaultOwner        = "joshyorko"
	defaultDescription  = "Dudley OS - a thin DSB product image built on Universal Blue"
	defaultKeywords     = "bootc,ublue,universal-blue"
	defaultLogoURL      = "https://avatars.githubusercontent.com/u/120078124?s=200&v=4"
	defaultBuildahImage = "quay.io/buildah/stable:v1.41"
	defaultTrivyImage   = "aquasec/trivy:latest"
	defaultCosignImage  = "gcr.io/projectsigstore/cosign:latest"
)

type releasePlanInput struct {
	Registry    string
	ImageName   string
	StableTag   string
	Owner       string
	SHA         string
	RefName     string
	PipelineURL string
	SourceURI   string
	Now         time.Time
}

type ReleasePlan struct {
	Image          string
	PrimaryRef     string
	TagRefs        []string
	Tags           []string
	Labels         []string
	SHA            string
	BuildSHA       string
	Date           string
	Created        string
	Version        string
	Repository     string
	RefName        string
	PipelineURL    string
	SourceURI      string
	SBOMName       string
	ProvenanceName string
	TLSVerify      bool
	TLSVerifyArg   string
}

type ReleaseSummary struct {
	Image                string
	PrimaryRef           string
	DigestRefs           []string
	Tags                 []string
	SBOMName             string
	ProvenanceName       string
	Published            bool
	PublishSkippedReason string
	SBOMGenerated        bool
	SBOMSkippedReason    string
	Signed               bool
	SignSkippedReason    string
	Attested             bool
	AttestSkippedReason  string
	BuildLog             string
}

func planRelease(input releasePlanInput) *ReleasePlan {
	now := input.Now.UTC()
	if now.IsZero() {
		now = time.Now().UTC()
	}

	registry := lowerDefault(input.Registry, defaultRegistry)
	imageName := lowerDefault(input.ImageName, defaultImageName)
	stableTag := defaultString(input.StableTag, defaultStableTag)
	owner := defaultString(input.Owner, defaultOwner)
	sha := strings.TrimSpace(input.SHA)
	buildSHA := sha
	if len(buildSHA) > 12 {
		buildSHA = buildSHA[:12]
	}

	date := now.Format("20060102")
	created := now.Format(time.RFC3339)
	version := fmt.Sprintf("%s.%s", stableTag, date)
	repository := fmt.Sprintf("https://github.com/%s/%s", owner, imageName)
	image := fmt.Sprintf("%s/%s", registry, imageName)
	tags := []string{stableTag, version, date}

	labels := []string{
		fmt.Sprintf("io.artifacthub.package.readme-url=https://raw.githubusercontent.com/%s/%s/%s/README.md", owner, imageName, sha),
		fmt.Sprintf("org.opencontainers.image.created=%s", created),
		fmt.Sprintf("org.opencontainers.image.description=%s", defaultDescription),
		fmt.Sprintf("org.opencontainers.image.documentation=https://raw.githubusercontent.com/%s/%s/%s/README.md", owner, imageName, sha),
		fmt.Sprintf("org.opencontainers.image.source=%s/blob/%s/Containerfile", repository, sha),
		fmt.Sprintf("org.opencontainers.image.title=%s", imageName),
		fmt.Sprintf("org.opencontainers.image.url=%s/tree/%s", repository, sha),
		fmt.Sprintf("org.opencontainers.image.vendor=%s", owner),
		fmt.Sprintf("org.opencontainers.image.version=%s", version),
		"io.artifacthub.package.deprecated=false",
		fmt.Sprintf("io.artifacthub.package.keywords=%s", defaultKeywords),
		"io.artifacthub.package.license=Apache-2.0",
		fmt.Sprintf("io.artifacthub.package.logo-url=%s", defaultLogoURL),
		"io.artifacthub.package.prerelease=false",
		"containers.bootc=1",
	}

	plan := &ReleasePlan{
		Image:          image,
		Tags:           tags,
		Labels:         labels,
		SHA:            sha,
		BuildSHA:       buildSHA,
		Date:           date,
		Created:        created,
		Version:        version,
		Repository:     repository,
		RefName:        input.RefName,
		PipelineURL:    input.PipelineURL,
		SourceURI:      defaultString(input.SourceURI, "local-source"),
		SBOMName:       fmt.Sprintf("%s-%s-%s.spdx.json", imageName, date, buildSHA),
		ProvenanceName: fmt.Sprintf("%s-%s-%s.provenance.json", imageName, date, buildSHA),
		TLSVerify:      tlsVerify(image),
		TLSVerifyArg:   tlsVerifyArg(image),
	}
	for _, tag := range tags {
		ref := fmt.Sprintf("%s:%s", image, tag)
		plan.TagRefs = append(plan.TagRefs, ref)
	}
	plan.PrimaryRef = plan.TagRefs[0]

	return plan
}

func provenancePredicate(plan *ReleasePlan) ([]byte, error) {
	predicate := map[string]any{
		"_type": "https://slsa.dev/provenance/v1",
		"buildDefinition": map[string]any{
			"buildType": "https://dagger.io/dudley/release-pipeline/v1",
			"externalParameters": map[string]any{
				"image":        plan.Image,
				"tags":         plan.Tags,
				"tagRefs":      plan.TagRefs,
				"sha":          plan.SHA,
				"refName":      plan.RefName,
				"pipelineURL":  plan.PipelineURL,
				"tlsVerify":    plan.TLSVerify,
				"sbom":         plan.SBOMName,
				"provenance":   plan.ProvenanceName,
				"imageFormat":  "docker",
				"buildTool":    "buildah",
				"sbomTool":     "trivy",
				"signingTool":  "cosign",
				"defaultImage": defaultImageName,
			},
			"internalParameters": map[string]any{},
			"resolvedDependencies": []map[string]any{
				{
					"uri": plan.SourceURI,
					"digest": map[string]string{
						"gitCommit": plan.SHA,
					},
				},
			},
		},
		"runDetails": map[string]any{
			"builder": map[string]any{
				"id": "dagger://dudley-os/release",
			},
			"metadata": map[string]any{
				"invocationID": plan.PipelineURL,
				"startedOn":    plan.Created,
				"finishedOn":   plan.Created,
			},
		},
	}

	return json.MarshalIndent(predicate, "", "  ")
}

func summaryFromPlan(plan *ReleasePlan) *ReleaseSummary {
	return &ReleaseSummary{
		Image:          plan.Image,
		PrimaryRef:     plan.PrimaryRef,
		Tags:           append([]string{}, plan.Tags...),
		SBOMName:       plan.SBOMName,
		ProvenanceName: plan.ProvenanceName,
	}
}

func lowerDefault(value, fallback string) string {
	return strings.ToLower(defaultString(value, fallback))
}

func defaultString(value, fallback string) string {
	if strings.TrimSpace(value) == "" {
		return fallback
	}
	return strings.TrimSpace(value)
}

func registryHost(image string) string {
	host, _, ok := strings.Cut(image, "/")
	if !ok {
		return image
	}
	return host
}

func tlsVerify(image string) bool {
	host := registryHost(image)
	return !(host == "localhost" || strings.HasPrefix(host, "localhost:") || host == "127.0.0.1" || strings.HasPrefix(host, "127.0.0.1:") || host == "[::1]" || strings.HasPrefix(host, "[::1]:"))
}

func tlsVerifyArg(image string) string {
	if tlsVerify(image) {
		return "--tls-verify=true"
	}
	return "--tls-verify=false"
}

func imageRepository(imageRef string) string {
	repository := imageRef
	if before, _, ok := strings.Cut(repository, "@"); ok {
		repository = before
	}
	lastSlash := strings.LastIndex(repository, "/")
	lastColon := strings.LastIndex(repository, ":")
	if lastColon > lastSlash {
		repository = repository[:lastColon]
	}
	return repository
}

func repositoryParts(imageRef string) (string, string) {
	repository := imageRepository(imageRef)
	lastSlash := strings.LastIndex(repository, "/")
	if lastSlash < 0 {
		return defaultRegistry, repository
	}
	return repository[:lastSlash], repository[lastSlash+1:]
}
