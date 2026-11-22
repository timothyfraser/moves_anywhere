# MOVES Anywhere guides

This is the index of the guides in this folder. Start with the [main README](../README.md), which explains how to run MOVES with Docker. The guides below go deeper. They are listed in a sensible reading order.

| Guide | What it is for |
|----|----|
| [MOVES inputs](README_MOVES_inputs.md) | Which input tables MOVES needs, and how MOVES Anywhere adapts them. |
| [County runs](README_county_runs.md) | Every `parameters.json` key, the columns of `data.csv`, emission rates, and how to add your own input tables. |
| [Project-scale runs](README_project_scale.md) | How to run individual road links and parking lots for one hour. |
| [Project scale: design, assumptions and limits](PROJECT_SCALE_DESIGN.md) | What MOVES needs at each scale, what is filled in and from where, what was measured, and how it can be wrong. |
| [Link sources (beta)](README_link_sources.md) | How `links.sh` builds project-scale links from federal road and elevation data, and its limits. |
| [The pipeline scripts](README_scripts.md) | What happens inside the container, step by step. Generated from the script headers. |
| [The run manifest](RUN_MANIFEST.md) | How to read `run_manifest.json`, the file that says a run finished. |
| [Run tickets](RUN_TICKET.md) | How to run MOVES Anywhere from your own cloud service. |
| [The replication kit](REPLICATION_KIT.md) | How to rerun a result on a stock MOVES install. |
| [The `catr` package](README_catr.md) | Writing runspecs and reading results in R. |
| [Version pins](PINS_v3.md) | The exact MOVES, R and package versions inside the image. |
| [Docker Hub overview](DOCKERHUB_OVERVIEW.md) | The short page shown on the Docker Hub listing, with links. |
| [Developer tools](README_dev.md) | Tools for building and testing the image yourself. |
| [The older base image](README_docker_moves.md) | The `docker_moves` base image, kept for reference. |
