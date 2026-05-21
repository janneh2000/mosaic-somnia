/** @type {import('next').NextConfig} */
const nextConfig = {
    reactStrictMode: true,
    transpilePackages: ["@mosaic/sdk"],
    webpack(config) {
        // viem ships ESM; ensure no fallback issues.
        return config;
    }
};
export default nextConfig;
