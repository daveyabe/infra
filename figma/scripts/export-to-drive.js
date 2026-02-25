#!/usr/bin/env node
/**
 * Export Figma file(s) top-level frames as PNGs and upload to Google Drive.
 *
 * Modes (one of):
 *   FIGMA_TEAM_ID       - Export all files in the team (team → projects → files). Drive: root/ProjectName/FileName/frames
 *   FIGMA_FILE_KEYS     - Comma-separated file keys. Drive: root/FileName/frames
 *   FIGMA_FILE_KEY      - Single file. Drive: root/frames (current behaviour)
 *
 * Required env:
 *   FIGMA_ACCESS_TOKEN  - Figma personal access token (needs projects:read for team mode)
 *   GOOGLE_DRIVE_FOLDER_ID - Drive folder ID (root for exports)
 *   Google auth: either GOOGLE_DRIVE_CREDENTIALS_JSON (service account key JSON) or Application Default
 *   Credentials (e.g. from GitHub Actions WIF via google-github-actions/auth)
 *
 * Optional:
 *   FIGMA_EXPORT_FORMAT      - png | jpg | svg | pdf (default: png)
 *   FIGMA_COMBINE_PDF_PER_FILE - when "true" or "1" and format is pdf, merge all frames into one PDF per file (e.g. one deck PDF)
 *   FIGMA_PROJECT_IDS       - Comma-separated project IDs (only with FIGMA_TEAM_ID) to limit to certain projects
 *   FIGMA_EDITOR_TYPES      - Comma-separated editor types to include (figma, figjam, slides). Default: all types.
 *
 * Note: The Figma REST API does not currently support Slides files (GET /v1/files/:key returns
 * "File type not supported"). Slides files are detected via the metadata endpoint and skipped
 * with a clear message. Regular Figma design files containing presentation frames export fine.
 */

import { Readable } from 'stream';
import { PDFDocument } from 'pdf-lib';
import { google } from 'googleapis';

const FIGMA_BASE = 'https://api.figma.com/v1';
const DELAY_BETWEEN_FILES_MS = 1500;
const MAX_RETRIES = 4;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** fetch() wrapper with automatic retry + backoff on 429 rate-limit responses. */
async function figmaFetch(url, opts = {}) {
  for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
    const res = await fetch(url, opts);
    if (res.status !== 429) return res;
    const retryAfter = Number(res.headers.get('retry-after')) || 0;
    const waitMs = retryAfter > 0 ? retryAfter * 1000 : 2000 * 2 ** attempt;
    console.log(`  [rate-limited, retrying in ${(waitMs / 1000).toFixed(1)}s]`);
    await sleep(waitMs);
  }
  return fetch(url, opts);
}

function env(name) {
  const v = process.env[name];
  if (!v) throw new Error(`Missing env: ${name}`);
  return v;
}

function envOptional(name) {
  return process.env[name] || '';
}

function sanitizeFileName(name) {
  return name.replace(/[^\w\s.-]/g, '').replace(/\s+/g, '_').trim() || 'frame';
}

/** Extract Drive folder ID from a URL or return as-is if already an ID. */
function normalizeDriveFolderId(value) {
  if (!value || typeof value !== 'string') return value;
  const trimmed = value.trim();
  if (!trimmed.includes('drive.google') && !trimmed.includes('/')) return trimmed;
  const foldersMatch = trimmed.match(/\/folders\/([a-zA-Z0-9_-]+)/);
  if (foldersMatch) return foldersMatch[1];
  const idParamMatch = trimmed.match(/[?&]id=([a-zA-Z0-9_-]+)/);
  if (idParamMatch) return idParamMatch[1];
  return trimmed;
}

/** Collect top-level frame/slide node ids and names (direct children of each page). */
function collectFrameNodes(document) {
  const acc = [];
  const pages = document.children || [];
  for (const page of pages) {
    for (const node of page.children || []) {
      if (node.type === 'FRAME' || node.type === 'SLIDE') {
        acc.push({ id: node.id, name: node.name });
      }
      if (node.type === 'SLIDE_ROW' || node.type === 'SLIDE_GRID') {
        for (const child of node.children || []) {
          if (child.type === 'SLIDE') acc.push({ id: child.id, name: child.name });
          if (child.type === 'SLIDE_ROW') {
            for (const slide of child.children || []) {
              if (slide.type === 'SLIDE') acc.push({ id: slide.id, name: slide.name });
            }
          }
        }
      }
    }
  }
  return acc;
}

/** List all files in a team: { fileKey, fileName, projectName }[]. */
async function listTeamFiles(token, teamId, { projectIdsFilter = [] } = {}) {
  const projectsRes = await figmaFetch(`${FIGMA_BASE}/teams/${teamId}/projects`, {
    headers: { 'X-Figma-Token': token },
  });
  if (!projectsRes.ok) throw new Error(`Figma team projects failed: ${projectsRes.status} ${await projectsRes.text()}`);
  const projectsData = await projectsRes.json();
  const projects = projectsData.projects || [];
  const files = [];
  for (const project of projects) {
    if (projectIdsFilter.length && !projectIdsFilter.includes(project.id)) continue;
    const filesRes = await figmaFetch(`${FIGMA_BASE}/projects/${project.id}/files`, {
      headers: { 'X-Figma-Token': token },
    });
    if (!filesRes.ok) continue;
    const filesData = await filesRes.json();
    const projectFiles = filesData.files || [];
    for (const f of projectFiles) {
      const fileKey = f.key ?? f.file_key ?? f.id;
      if (!fileKey) continue;
      files.push({
        fileKey,
        fileName: f.name || fileKey,
        projectName: project.name || project.id,
      });
    }
  }
  return files;
}

/** Ensure a folder path exists under parentId; create if needed. Returns folder id. */
async function ensureFolder(drive, parentId, folderName) {
  const safeName = sanitizeFileName(folderName) || 'folder';
  const list = await drive.files.list({
    q: `'${parentId}' in parents and name = '${safeName.replace(/'/g, "''")}' and mimeType = 'application/vnd.google-apps.folder' and trashed = false`,
    fields: 'files(id)',
    pageSize: 1,
    supportsAllDrives: true,
    includeItemsFromAllDrives: true,
  });
  if (list.data.files?.length) return list.data.files[0].id;
  const create = await drive.files.create({
    requestBody: {
      name: safeName,
      mimeType: 'application/vnd.google-apps.folder',
      parents: [parentId],
    },
    supportsAllDrives: true,
  });
  return create.data.id;
}

/**
 * Lightweight metadata check via GET /v1/files/:key/meta (Tier 3).
 * Returns { editorType } on success, or null if the endpoint isn't available for this file.
 */
async function fetchFileMeta(token, fileKey) {
  const res = await figmaFetch(`${FIGMA_BASE}/files/${fileKey}/meta`, {
    headers: { 'X-Figma-Token': token },
  });
  if (!res.ok) return null;
  const data = await res.json();
  return data.file || null;
}

const SLIDES_REST_API_UNSUPPORTED_MSG =
  'skipped (Figma Slides files are not yet supported by the REST API — export manually from Figma as PDF/PPTX).';

/** Export one file's frames and upload. resolveTargetFolder is called lazily (only when there's content to upload). Returns { count, skipReason? }. */
async function exportOneFile(token, fileKey, resolveTargetFolder, format, drive, opts = {}) {
  const { combinePdfPerFile = false, fileNameForDeck = '', editorTypes = [] } = opts;

  const meta = await fetchFileMeta(token, fileKey);
  if (meta) {
    if (meta.editorType === 'slides') {
      return { count: 0, skipReason: SLIDES_REST_API_UNSUPPORTED_MSG };
    }
    if (editorTypes.length && !editorTypes.includes(meta.editorType)) {
      return { count: 0, skipReason: `skipped (editor type "${meta.editorType}" not in [${editorTypes.join(', ')}]).` };
    }
  }

  const fileRes = await figmaFetch(`${FIGMA_BASE}/files/${fileKey}`, {
    headers: { 'X-Figma-Token': token },
  });
  if (!fileRes.ok) {
    const t = await fileRes.text();
    throw new Error(`Figma file request failed: ${fileRes.status} ${t}`);
  }
  const fileData = await fileRes.json();
  if (editorTypes.length && !editorTypes.includes(fileData.editorType)) {
    return { count: 0, skipReason: `skipped (editor type "${fileData.editorType}" not in [${editorTypes.join(', ')}]).` };
  }
  const document = fileData.document;
  if (!document) throw new Error('Figma file has no document');
  const frames = collectFrameNodes(document);
  if (frames.length === 0) return { count: 0 };
  const ids = frames.map((f) => f.id).join(',');
  const imgRes = await figmaFetch(
    `${FIGMA_BASE}/images/${fileKey}?ids=${encodeURIComponent(ids)}&format=${format}`,
    { headers: { 'X-Figma-Token': token } }
  );
  if (!imgRes.ok) throw new Error(`Figma images request failed: ${imgRes.status}`);
  const imgData = await imgRes.json();
  if (imgData.err) throw new Error(`Figma images error: ${imgData.err}`);
  const images = imgData.images || {};
  const downloads = [];
  for (const frame of frames) {
    const url = images[frame.id];
    if (!url) continue;
    const res = await fetch(url);
    if (!res.ok) throw new Error(`Download failed for ${frame.id}: ${res.status}`);
    const buffer = Buffer.from(await res.arrayBuffer());
    downloads.push({ name: frame.name, buffer });
  }
  if (downloads.length === 0) return { count: 0 };

  const targetFolderId = await resolveTargetFolder();
  const ext = format === 'svg' ? 'svg' : format === 'pdf' ? 'pdf' : format === 'jpg' ? 'jpg' : 'png';
  const mimeType = ext === 'pdf' ? 'application/pdf' : ext === 'svg' ? 'image/svg+xml' : `image/${ext}`;

  if (format === 'pdf' && combinePdfPerFile && downloads.length > 0) {
    const mergedPdf = await PDFDocument.create();
    for (const { buffer } of downloads) {
      const src = await PDFDocument.load(buffer);
      const pages = await mergedPdf.copyPages(src, src.getPageIndices());
      pages.forEach((p) => mergedPdf.addPage(p));
    }
    const mergedBytes = await mergedPdf.save();
    const combinedName = (fileNameForDeck || fileData.name || fileKey).replace(/\.pdf$/i, '');
    const fileName = `${sanitizeFileName(combinedName)}.pdf`;
    await drive.files.create({
      requestBody: { name: fileName, parents: [targetFolderId] },
      media: { mimeType: 'application/pdf', body: Readable.from(Buffer.from(mergedBytes)) },
      supportsAllDrives: true,
    });
    return { count: downloads.length };
  }

  for (const { name, buffer } of downloads) {
    const fileName = `${sanitizeFileName(name)}.${ext}`;
    await drive.files.create({
      requestBody: { name: fileName, parents: [targetFolderId] },
      media: { mimeType, body: Readable.from(buffer) },
      supportsAllDrives: true,
    });
  }
  return { count: downloads.length };
}

async function main() {
  const token = env('FIGMA_ACCESS_TOKEN');
  const folderId = normalizeDriveFolderId(env('GOOGLE_DRIVE_FOLDER_ID'));
  const credentialsJson = process.env.GOOGLE_DRIVE_CREDENTIALS_JSON;
  const format = (process.env.FIGMA_EXPORT_FORMAT || 'png').toLowerCase();
  const combinePdfPerFile = /^(1|true|yes)$/i.test(process.env.FIGMA_COMBINE_PDF_PER_FILE || '');
  const editorTypes = envOptional('FIGMA_EDITOR_TYPES').split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);

  const auth = credentialsJson
    ? new google.auth.GoogleAuth({
        credentials: JSON.parse(credentialsJson),
        scopes: ['https://www.googleapis.com/auth/drive.file'],
      })
    : new google.auth.GoogleAuth({
        scopes: ['https://www.googleapis.com/auth/drive.file'],
      });
  const drive = google.drive({ version: 'v3', auth });

  let filesToExport = [];
  const teamId = envOptional('FIGMA_TEAM_ID');
  const fileKeys = envOptional('FIGMA_FILE_KEYS').split(',').map((s) => s.trim()).filter(Boolean);
  const singleKey = envOptional('FIGMA_FILE_KEY');
  const projectIdsFilter = envOptional('FIGMA_PROJECT_IDS').split(',').map((s) => s.trim()).filter(Boolean);

  if (teamId) {
    console.log('Team mode: discovering files from team', teamId);
    filesToExport = await listTeamFiles(token, teamId, { projectIdsFilter });
    console.log(`Found ${filesToExport.length} file(s) across projects.`);
  } else if (fileKeys.length) {
    filesToExport = fileKeys.map((fileKey) => ({ fileKey, fileName: fileKey, projectName: '' }));
    console.log(`File list mode: ${filesToExport.length} file(s).`);
  } else if (singleKey) {
    filesToExport = [{ fileKey: singleKey, fileName: singleKey, projectName: '' }];
    console.log('Single file mode.');
  } else {
    throw new Error('Set one of FIGMA_TEAM_ID, FIGMA_FILE_KEYS, or FIGMA_FILE_KEY');
  }

  if (filesToExport.length === 0) {
    console.log('No files to export.');
    return;
  }

  let totalFrames = 0;
  for (const { fileKey, fileName, projectName } of filesToExport) {
    const resolveTargetFolder = async () => {
      if (filesToExport.length <= 1) return folderId;
      if (projectName) {
        const projectFolderId = await ensureFolder(drive, folderId, projectName);
        return ensureFolder(drive, projectFolderId, fileName);
      }
      return ensureFolder(drive, folderId, fileName);
    };
    process.stdout.write(`  ${fileName} (${fileKey}) → `);
    let result;
    try {
      result = await exportOneFile(token, fileKey, resolveTargetFolder, format, drive, {
        combinePdfPerFile,
        fileNameForDeck: fileName,
        editorTypes,
      });
    } catch (err) {
      const msg = err?.message || String(err);
      if (msg.includes('File type not supported by this endpoint')) {
        console.log('skipped (file type not supported by Figma REST API, e.g. blank template or FigJam).');
        continue;
      }
      if (msg.includes('File not found') || msg.includes('404')) {
        console.log('skipped (file not found or no access).');
        continue;
      }
      if (msg.includes('429') || msg.includes('Rate limit')) {
        console.log('skipped (rate limit still exceeded after retries).');
        continue;
      }
      throw err;
    }
    if (result.skipReason) {
      console.log(result.skipReason);
      continue;
    }
    totalFrames += result.count;
    console.log(`${result.count} frame(s).`);
    await sleep(DELAY_BETWEEN_FILES_MS);
  }
  console.log('Done. Total frames uploaded:', totalFrames);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
