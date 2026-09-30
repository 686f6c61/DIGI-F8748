# Divulgación responsable — ZTE PSIRT

**Estado:** Enviado por correo electrónico al equipo de seguridad de ZTE (ZTE PSIRT) el **22 de septiembre de 2026**.
**A la espera de:** acuse de recibo y número de seguimiento del caso.

---

## Contenido del reporte enviado

> Dear ZTE PSIRT Team,
>
> I am contacting you to responsibly disclose a security-related finding affecting the ZTE F8748 router.
>
> During research on an F8748 legitimately installed on my own Internet connection, I identified a method by which the device's factory/diagnostic functionality can be temporarily enabled and used to access information stored on the device, ultimately allowing recovery of the administrative credentials.
>
> The process does not rely on password brute-forcing. It is related to the design and implementation of the device's factory/diagnostic mechanisms and the way the necessary authentication material and configuration data are handled by the firmware.
>
> I have documented my research, reproduction steps, and proof-of-concept tooling here:
>
> <https://github.com/686f6c61/DIGI-F8748>
>
> Relevant device:
>
> - **Vendor:** ZTE
> - **Model:** ZTE F8748
> - **Environment tested:** DIGI deployment in Spain
> - **Access required:** Local network access to the router and legitimate access to the device being tested
> - **Research purpose:** Security research and administration of an authorized device
>
> The repository describes the complete process so that your engineering/security team can reproduce the behavior and evaluate whether other firmware versions or deployments may also be affected.
>
> My intention in reporting this is to help ZTE improve the security of the product. I would be happy to provide additional technical information, test potential firmware fixes, verify mitigations, or assist your engineering team in reproducing the issue if that would be useful.
>
> If you consider any information currently present in the public repository particularly sensitive and recommend that it be temporarily removed or redacted while you investigate, please let me know specifically which elements are concerned and I will review that request promptly.
>
> I would also appreciate confirmation that you have received this report and, if possible, a reference or tracking ID for the case.
>
> Please feel free to contact me if you need firmware version information, logs, additional reproduction details, or testing against an updated firmware build.
>
> Best regards,
>
> **Rafa**
> Security Researcher / Software Engineer
> GitHub: <https://github.com/686f6c61/DIGI-F8748>
