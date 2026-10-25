# ADR-0003: Two layers, one repository, one workflow

Status: Accepted · 2026-10-25

## Context

What runs in AWS (networks, EKS, data services) and what runs inside each cluster (gateway, observability, model serving) change at different speeds but depend on each other, and a cluster API is private.

## Decision

The repository holds **two layers**: `infrastructure/` (AWS resource sets) and `k8s-installs/` (one Terraform root per in-cluster component, one unit per component per cluster, with instance names for things a cluster holds several of). **One workflow** serves both; any infrastructure module change re-runs every k8s module's tests. EKS endpoints stay **private**: cluster units run on a **self-hosted runner in the management VPC**, AWS units on GitHub-hosted runners.

## Consequences

- k8s components find their cluster through `modules/cluster`, which reads core-platform's state.
- The runner must sit in a runner group restricted to this workflow on `main`; fork pull requests never schedule cluster units.
- Networking (transit gateway, routes to the management VPC) is a prerequisite, still to build.
