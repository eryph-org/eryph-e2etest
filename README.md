# eryph-e2etest
Contains end-to-end tests for eryph.

## Run tests locally
You can run the tests locally as follows:
1. Install the Powershell modules `Pester`, `Assert` and `Posh-SSH`
2. Update the `settings.json` to reflect your local environment
3. Start eryph-zero
4. Open this repository in VS Code as administrator
5. Make sure the Pester extension is installed. Visual Studio should prompt you.
6. Run the desired test(s) in the VS Code test explorer

## Notes
- Powershell strict mode `Set-StrictMode` is not used as it is not supported
  by Pester v5. Both the `Assert` module and Pester's builtin assertions will
  e.g. access missing properties without checks or error handling.
