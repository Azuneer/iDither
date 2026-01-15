# iDither

<p align="center">
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="Swift 6.0">
  <img src="https://img.shields.io/badge/Platform-macOS%2014.0%2B-000000?style=for-the-badge&logo=apple&logoColor=white" alt="Platform macOS">
  <img src="https://img.shields.io/badge/Render-Metal-666666?style=for-the-badge&logo=apple&logoColor=white" alt="Metal">
  <img src="https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge" alt="License: MIT">
</p>

<p align="center">
  <img src="./assets/img/iDither.png" alt="iDither temporary logo" width="800">
</p>

<br>

iDither est une application macOS native dédiée au traitement d'images par dithering. Elle exploite la puissance de Metal pour transformer des images en visuels rétro, lo-fi ou texturés avec un rendu en temps réel.

## Fonctionnalités

### Algorithmes de Dithering
L'application propose plusieurs méthodes de diffusion et de trammage pour s'adapter à différents styles esthétiques :
- **Matrices ordonnées** : Bayer (2x2, 4x4, 8x8) et Cluster (4x4, 8x8).
- **Bruit** : Blue Noise approximé.
- **Diffusion d'erreur** : Floyd-Steinberg pour un rendu plus organique.

### Pré-traitement et Quantisation
- Ajustement en direct de la luminosité et du contraste.
- Contrôle de l'échelle des pixels (Pixel Scale) pour un effet pixel art.
- Gestion de la profondeur des couleurs (1 à 32 niveaux) et mode niveaux de gris (1-bit).

### Mode Chaos / FX
Un moteur d'effets intégré permet d'aller au-delà du dithering classique en introduisant des imperfections contrôlées :
- **Distorsion de motif** : Rotation et décalage (jitter) des matrices de dithering.
- **Glitch spatial** : Déplacement de pixels, turbulence et aberration chromatique.
- **Manipulation de seuil** : Injection de bruit et distorsion ondulatoire.
- **Chaos de quantification** : Variation aléatoire de la profondeur de bits et de la palette.

### Exportation
- Formats supportés : PNG, TIFF, JPEG.
- Mise à l'échelle à l'export (1x, 2x, 4x) pour conserver la netteté sur les écrans haute densité.
- Options pour préserver les métadonnées et aplatir la transparence.

## Technologies

Le projet est développé en Swift 6.0 et utilise SwiftUI pour l'interface et Metal pour le pipeline de rendu graphique, assurant des performances optimales même lors de la manipulation de paramètres complexes.

## Utilisation

1. Glissez une image dans la fenêtre principale ou utilisez le bouton d'importation.
2. Sélectionnez un algorithme et ajustez les paramètres dans la barre latérale.
3. Exportez le résultat final via le bouton d'exportation situé dans la barre d'outils.

Compatible avec macOS 14.0 et versions ultérieures.