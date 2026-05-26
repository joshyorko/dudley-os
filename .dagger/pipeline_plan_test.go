package main

import (
	"encoding/json"
	"reflect"
	"strings"
	"testing"
	"time"
)

func TestDudleyOsReleasePlanTagsAndLabels(t *testing.T) {
	now := time.Date(2026, 5, 26, 17, 45, 0, 0, time.UTC)
	plan := planRelease(releasePlanInput{
		Registry:  "ghcr.io/JoshYorko",
		ImageName: "Dudley-OS",
		Owner:     "JoshYorko",
		StableTag: "stable",
		SHA:       "abcdef1234567890",
		Now:       now,
	})

	if plan.Image != "ghcr.io/joshyorko/dudley-os" {
		t.Fatalf("image = %q", plan.Image)
	}

	wantTags := []string{"stable", "stable.20260526", "20260526"}
	if !reflect.DeepEqual(plan.Tags, wantTags) {
		t.Fatalf("tags = %#v, want %#v", plan.Tags, wantTags)
	}

	if plan.Version != "stable.20260526" {
		t.Fatalf("version = %q", plan.Version)
	}
	if plan.BuildSHA != "abcdef123456" {
		t.Fatalf("build sha = %q", plan.BuildSHA)
	}

	labels := strings.Join(plan.Labels, "\n")
	for _, want := range []string{
		"org.opencontainers.image.created=2026-05-26T17:45:00Z",
		"org.opencontainers.image.version=stable.20260526",
		"org.opencontainers.image.source=https://github.com/JoshYorko/dudley-os/blob/abcdef1234567890/Containerfile",
		"containers.bootc=1",
	} {
		if !strings.Contains(labels, want) {
			t.Fatalf("labels did not include %q:\n%s", want, labels)
		}
	}
}

func TestDudleyOsReleasePlanDisablesTLSForLoopbackRegistries(t *testing.T) {
	for _, registry := range []string{"localhost", "localhost:5000", "127.0.0.1", "127.0.0.1:5000", "[::1]", "[::1]:5000"} {
		plan := planRelease(releasePlanInput{
			Registry:  registry,
			ImageName: "dudley-os",
			SHA:       "abcdef1234567890",
			Now:       time.Date(2026, 5, 26, 0, 0, 0, 0, time.UTC),
		})

		if plan.TLSVerify {
			t.Fatalf("%s: TLSVerify = true", registry)
		}
		if plan.TLSVerifyArg != "--tls-verify=false" {
			t.Fatalf("%s: TLSVerifyArg = %q", registry, plan.TLSVerifyArg)
		}
	}
}

func TestDudleyOsRepositoryPartsDeriveImageMetadataFromRef(t *testing.T) {
	registry, imageName := repositoryParts("registry.gitlab.com/group/subgroup/dudley-os@sha256:abc123")
	if registry != "registry.gitlab.com/group/subgroup" {
		t.Fatalf("registry = %q", registry)
	}
	if imageName != "dudley-os" {
		t.Fatalf("imageName = %q", imageName)
	}
}

func TestDudleyOsProvenanceIncludesPortableReleaseContext(t *testing.T) {
	plan := planRelease(releasePlanInput{
		Registry:    "registry.gitlab.com/group",
		ImageName:   "dudley-os",
		Owner:       "joshyorko",
		StableTag:   "stable",
		SHA:         "abcdef1234567890",
		RefName:     "main",
		PipelineURL: "https://gitlab.example/pipelines/42",
		SourceURI:   "https://gitlab.example/group/dudley-os",
		Now:         time.Date(2026, 5, 26, 17, 45, 0, 0, time.UTC),
	})

	predicate, err := provenancePredicate(plan)
	if err != nil {
		t.Fatalf("provenancePredicate returned error: %v", err)
	}

	var decoded map[string]any
	if err := json.Unmarshal(predicate, &decoded); err != nil {
		t.Fatalf("predicate is not json: %v", err)
	}

	body := string(predicate)
	for _, want := range []string{
		"https://slsa.dev/provenance/v1",
		"abcdef1234567890",
		"registry.gitlab.com/group/dudley-os:stable",
		"main",
		"https://gitlab.example/pipelines/42",
		"https://gitlab.example/group/dudley-os",
	} {
		if !strings.Contains(body, want) {
			t.Fatalf("predicate did not include %q:\n%s", want, body)
		}
	}
}
