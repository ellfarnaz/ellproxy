# Contributing to EllProxy

<p align="center">
  <img src="icon.png" width="128" height="128" alt="EllProxy Icon">
</p>

Thank you for your interest in contributing to EllProxy! We welcome contributions from the community to help make this the best local AI proxy tool.

## How to Contribute

1.  **Fork the repository** on GitHub.
2.  **Clone your fork** locally:
    ```bash
    git clone https://github.com/YOUR_USERNAME/ellproxy.git
    cd ellproxy
    ```
3.  **Create a new branch** for your feature or bugfix:
    ```bash
    git checkout -b feature/my-new-feature
    ```
4.  **Make your changes**.
5.  **Commit your changes** with a clear message:
    ```bash
    git commit -m "feat: Add support for X provider"
    ```
6.  **Push to your fork**:
    ```bash
    git push origin feature/my-new-feature
    ```
7.  **Open a Pull Request** on the main repository.

## Development Setup

### Prerequisites
- macOS 14.0+ (Apple Silicon)
- Xcode 15+
- Swift 5.9+

### Building the Project
Run the build script to compile the app and bundle dependencies:
```bash
./create-app-bundle.sh
```

To run the app directly from Xcode, open `src/EllProxy.xcodeproj`.

## Project Structure

- `src/Sources/App`: Main application lifecycle.
- `src/Sources/Services`: Core logic (Routing, Sync, Auth).
- `src/Sources/Views`: SwiftUI views.
- `src/Sources/ThinkingProxy`: Logic for "Thinking" model support.
- `src/Sources/QuickSetup`: Auto-configuration logic for external tools.

## Coding Standards

- Follow standard Swift API Design Guidelines.
- Use distinct commit messages (e.g., `feat:`, `fix:`, `docs:`).
- Ensure your code supports macOS 14.0+.

## Submitting Pull Requests

- Describe what your changes do clearly.
- Link to any relevant issues.
- If adding a new feature, please include a screenshot or recording if applicable.

Thank you for contributing!
