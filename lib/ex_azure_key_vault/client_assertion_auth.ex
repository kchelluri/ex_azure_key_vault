defmodule ExAzureKeyVault.ClientAssertionAuth do
  @moduledoc """
  Internal module for getting authentication token for Azure connection using client assertion.
  """
  alias __MODULE__
  alias ExAzureKeyVault.HTTPUtils

  @enforce_keys [:client_id, :tenant_id, :cert_thumbprint, :private_key_pem]
  defstruct(
    client_id: nil,
    tenant_id: nil,
    cert_thumbprint: nil,
    private_key_pem: nil
  )

  @type t :: %__MODULE__{
    client_id: String.t,
    tenant_id: String.t,
    cert_thumbprint: String.t,
    private_key_pem: String.t
  }

  @doc """
  Creates `%ExAzureKeyVault.ClientAssertionAuth{}` struct with account tokens.

  ## Examples

      iex(1)> ExAzureKeyVault.ClientAssertionAuth.new("6f185f82-9909...", "6f1861e4-9909...", "934367bf1c97033...", "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEF")
      %ExAzureKeyVault.Auth{
        client_id: "6f185f82-9909...",
        tenant_id: "6f1861e4-9909...",
        cert_thumbprint: "934367bf1c97033...",
        private_key_pem: "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEF"
      }

  """
  @spec new(String.t, String.t, String.t, String.t) :: ClientAssertionAuth.t
  def new(client_id, tenant_id, cert_thumbprint, private_key_pem) do
    %ClientAssertionAuth{client_id: client_id, tenant_id: tenant_id, cert_thumbprint: cert_thumbprint, private_key_pem: private_key_pem}
  end

  @doc """
  Returns client assertion for Azure connection.

  ## Examples

      iex(1)> ExAzureKeyVault.ClientAssertionAuth.new("6f185f82-9909...", "6f1861e4-9909...", "934367bf1c97033...", "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEF")
      ...(1)> |> ExAzureKeyVault.ClientAssertionAuth.get_client_assertion()
      {:ok, "eyJ4NXQiOiIxMTEzIiwiYWxnIjoiUlM1MTI..."}

  """
  @spec get_client_assertion(ClientAssertionAuth.t) :: {:ok, String.t} | {:error, any}
  def get_client_assertion(%ClientAssertionAuth{} = params) do
    signer = Joken.Signer.create("RS256", %{"pem" => params.private_key_pem}, %{"x5t" => params.cert_thumbprint})
    sub = params.client_id
    iss = params.client_id
    jti = Joken.generate_jti()
    nbf = Joken.current_time()
    exp = Joken.current_time() + 600 # 10 minutes
    aud = "https://login.windows.net/#{params.tenant_id}/oauth2/token"
    {:ok, claims} = Joken.generate_claims(%{}, %{sub: sub, iss: iss, jti: jti, nbf: nbf, exp: exp, aud: aud})
    {:ok, jwt, _} = Joken.encode_and_sign(claims, signer)
    {:ok, jwt}
  end

  @doc """
  Returns bearer token for Azure connection.

  ## Examples

      iex(1)> ExAzureKeyVault.ClientAssertionAuth.new("6f185f82-9909...", "6f1861e4-9909...")
      ...(1)> |> ExAzureKeyVault.ClientAssertionAuth.get_client_assertion()
      ...(1)> |> ExAzureKeyVault.ClientAssertionAuth.get_bearer_token()
      {:ok, "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."}

  """
  @spec get_bearer_token(ClientAssertionAuth.t, String.t) :: {:ok, String.t} | {:error, any}
  def get_bearer_token(%ClientAssertionAuth{} = params, client_assertion) do
    url = auth_url(params.tenant_id)
    body = auth_body(params.client_id, client_assertion)
    headers = HTTPUtils.headers_form_urlencoded
    options = HTTPUtils.options_ssl
    case HTTPoison.post(url, body, headers, options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        response = Poison.decode!(body)
        {:ok, "Bearer #{response["access_token"]}"}
      {:ok, %HTTPoison.Response{status_code: status, body: ""}} ->
        HTTPUtils.response_client_error_or_ok(status, url)
      {:ok, %HTTPoison.Response{status_code: status, body: body}} ->
        HTTPUtils.response_client_error_or_ok(status, url, body)
      {:error, %HTTPoison.Error{reason: :nxdomain}} ->
        HTTPUtils.response_server_error(:nxdomain, url)
      {:error, %HTTPoison.Error{reason: reason}} ->
        HTTPUtils.response_server_error(reason)
      _ ->
        {:error, "Something went wrong"}
    end
  end

  @spec auth_url(String.t) :: String.t
  defp auth_url(tenant_id) do
    "https://login.windows.net/#{tenant_id}/oauth2/token"
  end

  @spec auth_body(String.t, String.t) :: tuple
  defp auth_body(client_id, client_assertion) do
    {:form, [
      grant_type: "client_credentials",
      client_id: client_id,
      client_assertion: client_assertion,
      client_assertion_type: "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
      resource: "https://vault.azure.net"
    ]}
  end
end
