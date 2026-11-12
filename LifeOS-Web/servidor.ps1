# LifeOS - servidor local minimo (somente leitura dos arquivos do app).
# Escuta apenas em http://localhost:8765 (nao fica acessivel pela rede).
# Os SEUS DADOS nao passam por aqui: ficam cifrados no armazenamento do navegador.
param([int]$Port = 8765)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($PSScriptRoot)
$mime = @{
  '.html' = 'text/html; charset=utf-8'; '.js' = 'text/javascript; charset=utf-8'; '.css' = 'text/css; charset=utf-8'
  '.json' = 'application/json'; '.webmanifest' = 'application/manifest+json'; '.svg' = 'image/svg+xml'
  '.png' = 'image/png'; '.ico' = 'image/x-icon'; '.txt' = 'text/plain; charset=utf-8'; '.md' = 'text/plain; charset=utf-8'
}
$blocked = @('.ps1', '.bat', '.cmd')

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
try { $listener.Start() } catch {
  Write-Host "Nao foi possivel usar a porta $Port (talvez o LifeOS ja esteja aberto)." -ForegroundColor Yellow
  exit 1
}
Write-Host "LifeOS rodando em http://localhost:$Port  (feche esta janela para parar)" -ForegroundColor Green

while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  $res = $ctx.Response
  try {
    $path = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath.TrimStart('/'))
    if ([string]::IsNullOrEmpty($path)) { $path = 'index.html' }
    $full = [IO.Path]::GetFullPath((Join-Path $root $path))
    $ext = [IO.Path]::GetExtension($full).ToLower()
    if (-not $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -or $blocked -contains $ext -or -not (Test-Path $full -PathType Leaf)) {
      $res.StatusCode = 404
    } else {
      $bytes = [IO.File]::ReadAllBytes($full)
      $res.ContentType = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { 'application/octet-stream' }
      $res.Headers.Add('X-Content-Type-Options', 'nosniff')
      $res.Headers.Add('Cache-Control', 'no-cache')
      $res.ContentLength64 = $bytes.Length
      $res.OutputStream.Write($bytes, 0, $bytes.Length)
    }
  } catch { $res.StatusCode = 500 }
  finally { $res.Close() }
}
