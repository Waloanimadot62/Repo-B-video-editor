# ✂️ video-editor

This repository contains the GitHub Action workflow and scripts dedicated to taking a single video part, applying specific vertical (9:16) editing transformations, and uploading the final result to a configured Google Drive/Rclone destination.

It acts as the second stage of the video pipeline, triggered by the n8n orchestrator after the initial video splitting job (from **Repo A**) is complete.

## 🛠️ Prerequisites

Before this repository can function, the following must be configured:

1.  **`RCLONE_CONF_B64`**: The **Base64-encoded string** of your `rclone.conf` file, necessary for downloading the input part and uploading the final edited video. This must be set as a **GitHub Secret**.
2.  **GitHub Actions Permissions**: The default `GITHUB_TOKEN` must have permission to **write** to the repository to commit the result file.

---

## ⚙️ How It Works (Per-Part Job Flow)

The workflow is triggered by the creation of a job file in the `jobs/edit/` directory, which represents a single video part to be processed.

1.  **Trigger**: The n8n orchestrator pushes a job file to the `jobs/edit/` directory (e.g., `jobs/edit/<jobId>-part<N>.json`).
2.  **Execution**: The script `./scripts/edit_part.sh` runs.
    * It **downloads** the specific video part identified by the `input_url`.
    * It uses **FFmpeg** to apply the vertical 9:16 transformation:
        * Creates a **blurred background** from the input.
        * Scales and overlays the original video in the center.
        * Adds **text overlays** (movie title and part index).
    * It **uploads** the final edited part to the target `output_folder` using Rclone.
3.  **Signal Completion**: The script commits a result JSON file (`jobs/edit_results/<jobId>-part<N>.json`) back to the repo, containing the final remote link.
4.  **Next Step**: n8n polls for this file to update the Google Sheet with the final link.

---

## 📥 Job Input Structure (`jobs/edit/<jobId>-part<N>.json`)

The job file created by n8n must be a JSON object detailing a single part:

| Field Name | Type | Description | Example |
| :--- | :--- | :--- | :--- |
| `input_url` | String | The Rclone remote path or link to the split video part (from **Repo A**'s output). | `gdrive:Processed/Splits/MyMovie_part1.mp4` |
| `movie_title` | String | The main title used for the text overlay. | `"My Awesome Documentary"` |
| `part_index` | Integer | The index of the part (e.g., 1). Used in the filename and text overlay. | `1` |
| `output_folder` | String | The Rclone remote path where the final edited file will be uploaded. | `gdrive:Processed/Final` |

### **Example Job File**

```json
{
  "input_url": "gdrive:Processed/Splits/MyMovie_part1.mp4",
  "movie_title": "My Movie",
  "part_index": 1,
  "output_folder": "gdrive:Processed/Final"
}
