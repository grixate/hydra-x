defmodule HydraXWeb.PageController do
  use HydraXWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def product(conn, _params) do
    # Serve the Vite-built SPA for all /product/* routes.
    # In dev, Vite dev server handles this via proxy.
    # In prod, serve the built index.html from priv/static/product/.
    index_path = Path.join(:code.priv_dir(:hydra_x), "static/product/index.html")

    if File.exists?(index_path) do
      conn
      |> put_resp_content_type("text/html")
      |> send_file(200, index_path)
    else
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(200, """
      <!DOCTYPE html>
      <html><head><title>Hydra Product</title></head>
      <body><div id="root"></div>
      <script>document.body.innerHTML = '<p style="padding:2rem;font-family:sans-serif">Product app not built. Run <code>cd web && npm run build</code> or use the Vite dev server.</p>';</script>
      </body></html>
      """)
    end
  end
end
