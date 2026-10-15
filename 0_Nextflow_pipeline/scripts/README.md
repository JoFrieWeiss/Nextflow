# Scripts

Helper scripts used by the **EnviHoli / Nextflow** pipeline (see the main [`README.md`](../README.md)).

All scripts in this directory are taken from EnviHoli (external_scripts/, commit dcc08b7; archived on Zenodo: 10.5281/zenodo.17974857). They are included here in the versions used for the publication.

The scripts are called automatically from within the Nextflow processes. The descriptions below document what each one does and which arguments it expects, in case you need to run or debug them manually.

| Script | Language | Purpose |
|--------|----------|---------|
| [`post-metadmg-lca.R`](#post-metadmg-lcar) | R | Parse a metaDMG `*.lca.txt.gz` file and attach the full taxonomic lineage |
| [`combine_lca.R`](#combine_lcar) | R | Merge all per-sample LCA tables into one `RData` object |
| [`combine_dmgout.R`](#combine_dmgoutr) | R | Merge all per-sample metaDMG output tables into one `RData` object |
| [`mismatch.R`](#mismatchr) | R | Combine `*.mismatches.txt.gz` files and compute substitution frequencies |
| [`dedup_sam.py`](#dedup_sampy) | Python 3 | Remove duplicate `@SQ` header lines from a SAM file |

> All R scripts load `readr` and `dplyr` (`post-metadmg-lca.R` also `stringr`). Make sure these packages are available in your R environment / module.

---

## `post-metadmg-lca.R`

Reads a metaDMG `*.lca.txt.gz` file, attaches the key ranks (species, genus, family, order, class, phylum, kingdom, superkingdom) and the full lineage, and writes a tab-separated `*.taxlineage.tsv` file.

**What it does**
1. Reads `*.lca.txt.gz` (metaDMG output).
2. Builds a taxonomic lineage table from the NCBI `nodes`, full-lineage and ranked-lineage files.
3. Aggregates read counts per taxon, joins the lineage, and writes the result.
4. Rows whose lineage could not be resolved are written to a separate `*.no.taxlineage.tsv` file.

**Arguments** (positional)

| # | Argument | Description |
|---|----------|-------------|
| 1 | input/output directory | folder containing the `.lca.txt.gz` file and where output is written |
| 2 | sample name | used as filename prefix and stored in the `sample` column |
| 3 | file suffix | e.g. `.lca.txt.gz` |
| 4 | full lineage file | NCBI full-lineage table (TSV) |
| 5 | ranked lineage file | NCBI ranked-lineage table (TSV) |
| 6 | nodes file | NCBI `nodes.dmp` (ranks) |

**Output**
- `<sample><suffix>.taxlineage.tsv` — taxon reads with full lineage
- `<sample><suffix>.no.taxlineage.tsv` — only written if some taxa had no lineage

```bash
Rscript post-metadmg-lca.R <dir> <sample> <.lca.txt.gz> <fulllineage.tsv> <rankedlineage.tsv> <nodes.dmp>
```

---

## `combine_lca.R`

Combines all per-sample LCA tables (the `*.taxlineage.tsv` produced above) into a single merged `RData` object, with sample metadata attached.

**Arguments** (positional)

| # | Argument | Description |
|---|----------|-------------|
| 1 | `FILES` | directory to search (recursively) for input files |
| 2 | `FILE_END` | file-ending pattern to match (matched at end of name) |
| 3 | `SAMPLES` | metadata CSV, joined by the `sample` column |
| 4 | `OUT_TAB` | output directory |
| 5 | `OUT_FILE_NAME` | prefix for the output file |

**Output**: `<OUT_TAB>/<OUT_FILE_NAME>_MergedData.RData`

```bash
Rscript combine_lca.R <FILES> <FILE_END> <samples.csv> <OUT_TAB> <OUT_FILE_NAME>
```

---

## `combine_dmgout.R`

Combines all per-sample metaDMG output tables (`*_metaDMGout.csv` / taxlineage CSVs) into a single merged `RData` object, with sample metadata **and** taxonomic lineage attached.

**Arguments** (positional)

| # | Argument | Description |
|---|----------|-------------|
| 1 | `FILES` | directory to search (recursively) for input files |
| 2 | `FILE_END` | file-ending pattern to match |
| 3 | `END_IN_FILE` | string stripped from the `sample` column |
| 4 | `SAMPLES` | metadata CSV, joined by the `sample` column |
| 5 | `TAXLI` | taxlineage `RData` file (loads object `taxlineage`), joined by `tax_id` |
| 6 | `OUT_TAB` | output directory |
| 7 | `OUT_FILE_NAME` | prefix for the output file |

**Output**: `<OUT_TAB>/<OUT_FILE_NAME>_MergedData.RData`

```bash
Rscript combine_dmgout.R <FILES> <FILE_END> <END_IN_FILE> <samples.csv> <taxlineage.RData> <OUT_TAB> <OUT_FILE_NAME>
```

---

## `mismatch.R`

Combines all `*.mismatches.txt.gz` files, computes the frequency of each paired-nucleotide substitution (per read direction and position), and merges all libraries into one `RData` file with sample metadata and taxonomic lineage attached.

**Arguments** (positional)

| # | Argument | Description |
|---|----------|-------------|
| 1 | `FILES` | directory to search (recursively) for input files |
| 2 | `FILE_END` | file-ending pattern to match (also stripped to derive `sample`) |
| 3 | `SAMPLES` | metadata CSV, joined by the `sample` column |
| 4 | `TAXLI` | taxlineage `RData` file (loads object `taxlineage`), joined by `tax_id` |
| 5 | `OUT_TAB` | output directory |
| 6 | `OUT_FILE_NAME` | prefix for the output file |

**Output**: `<OUT_TAB>/<OUT_FILE_NAME>_MergedData.RData` (object `all_freq_li`)

```bash
Rscript mismatch.R <FILES> <FILE_END> <samples.csv> <taxlineage.RData> <OUT_TAB> <OUT_FILE_NAME>
```

---

## `dedup_sam.py`

Removes duplicate `@SQ` header lines from a SAM file (keeping the first occurrence of each sequence name / `SN:`). The data section is passed through unchanged.

**Arguments** (positional)

| # | Argument | Description |
|---|----------|-------------|
| 1 | `input.sam` | input SAM file |
| 2 | `output.sam` | output SAM file |

```bash
python3 dedup_sam.py input.sam output.sam
```
