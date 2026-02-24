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
 */

import { Readable } from 'stream';
import { PDFDocument } from 'pdf-lib';
import { google } from 'googleapis';

const FIGMA_BASE = 'https://api.figma.com/v1';

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

/** Collect top-level frame node ids and names (direct children of each page). */
function collectFrameNodes(document) {
  const acc = [];
  const pages = document.children || [];
  for (const page of pages) {
    const nodes = page.children || [];
    for (const node of nodes) {
      if (node.type === 'FRAME') acc.push({ id: node.id, name: node.name });
    }
  }
  return acc;
}

/** List all files in a team: { fileKey, fileName, projectName }[]. */
async function listTeamFiles(token, teamId, projectIdsFilter = []) {
  const projectsRes = await fetch(`${FIGMA_BASE}/teams/${teamId}/projects`, {
    headers: { 'X-Figma-Token': token },
  });
  if (!projectsRes.ok) throw new Error(`Figma team projects failed: ${projectsRes.status} ${await projectsRes.text()}`);
  const projectsData = await projectsRes.json();
  const projects = projectsData.projects || [];
  const files = [];
  for (const project of projects) {
    if (projectIdsFilter.length && !projectIdsFilter.includes(project.id)) continue;
    const filesRes = await fetch(`${FIGMA_BASE}/projects/${project.id}/files`, {
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
  });
  if (list.data.files?.length) return list.data.files[0].id;
  const create = await drive.files.create({
    requestBody: {
      name: safeName,
      mimeType: 'application/vnd.google-apps.folder',
      parents: [parentId],
    },
  });
  return create.data.id;
}

/** Export one file's frames and upload to targetFolderId. If combinePdfPerFile and format is pdf, upload one merged PDF. */
async function exportOneFile(token, fileKey, targetFolderId, format, drive, opts = {}) {
  const { combinePdfPerFile = false, fileNameForDeck = '' } = opts;
  const fileRes = await fetch(`${FIGMA_BASE}/files/${fileKey}`, {
    headers: { 'X-Figma-Token': token },
  });
  if (!fileRes.ok) {
    const t = await fileRes.text();
    throw new Error(`Figma file request failed: ${fileRes.status} ${t}`);
  }
  const fileData = await fileRes.json();
  const document = fileData.document;
  if (!document) throw new Error('Figma file has no document');
  const frames = collectFrameNodes(document);
  if (frames.length === 0) return 0;
  const ids = frames.map((f) => f.id).join(',');
  const imgRes = await fetch(
    `${FIGMA_BASE}/images/${fileKey}?ids=${encodeURIComponent(ids)}&format=${format}`,
    { headers: { 'X-Figma-Token': token } }
  );
  if (!imgRes.ok) throw new Error(`Figma images request failed: ${imgRes.status}`);
  const imgData = await imgRes.json();
  if (imgData.err) throw new Error(`Figma images error: ${imgData.err}`);
  const images = imgData.images || {};
  // Preserve frame order when downloading (important for combined PDF)
  const downloads = [];
  for (const frame of frames) {
    const url = images[frame.id];
    if (!url) continue;
    const res = await fetch(url);
    if (!res.ok) throw new Error(`Download failed for ${frame.id}: ${res.status}`);
    const buffer = Buffer.from(await res.arrayBuffer());
    downloads.push({ name: frame.name, buffer });
  }
  if (downloads.length === 0) return 0;
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
    });
    return downloads.length;
  }

  for (const { name, buffer } of downloads) {
    const fileName = `${sanitizeFileName(name)}.${ext}`;
    await drive.files.create({
      requestBody: { name: fileName, parents: [targetFolderId] },
      media: { mimeType, body: Readable.from(buffer) },
    });
  }
  return downloads.length;
}

async function main() {
  const token = env('FIGMA_ACCESS_TOKEN');
  const folderId = env('GOOGLE_DRIVE_FOLDER_ID');
  const credentialsJson = process.env.GOOGLE_DRIVE_CREDENTIALS_JSON;
  const format = (process.env.FIGMA_EXPORT_FORMAT || 'png').toLowerCase();
  const combinePdfPerFile = /^(1|true|yes)$/i.test(process.env.FIGMA_COMBINE_PDF_PER_FILE || '');

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
    filesToExport = await listTeamFiles(token, teamId, projectIdsFilter.length ? projectIdsFilter : undefined);
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
    let targetFolderId = folderId;
    if (filesToExport.length > 1) {
      if (projectName) {
        const projectFolderId = await ensureFolder(drive, folderId, projectName);
        targetFolderId = await ensureFolder(drive, projectFolderId, fileName);
      } else {
        targetFolderId = await ensureFolder(drive, folderId, fileName);
      }
    }
    process.stdout.write(`  ${fileName} (${fileKey}) → `);
    let count = 0;
    try {
      count = await exportOneFile(token, fileKey, targetFolderId, format, drive, {
        combinePdfPerFile,
        fileNameForDeck: fileName,
      });
    } catch (err) {
      const msg = err?.message || String(err);
      if (msg.includes('File type not supported by this endpoint')) {
        console.log('skipped (file type not supported by Figma API, e.g. blank template or FigJam).');
        continue;
      }
      throw err;
    }
    totalFrames += count;
    console.log(`${count} frame(s).`);
  }
  console.log('Done. Total frames uploaded:', totalFrames);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
