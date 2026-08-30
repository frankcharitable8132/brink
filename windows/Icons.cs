using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using Path = System.Windows.Shapes.Path;

namespace Brink;

/// Vector provider icons, carried over from the macOS app's mockup paths
/// (both defined in a 24×24 box and scaled to the requested size).
public static class Icons
{
    /// Claude "asterisk burst": 8 stroked lines.
    private static Geometry ClaudeGeometry(double size)
    {
        double s = size / 24.0;
        var g = new GeometryGroup();
        (double x1, double y1, double x2, double y2)[] lines =
        {
            (12, 2.5, 12, 8), (12, 16, 12, 21.5), (2.5, 12, 8, 12), (16, 12, 21.5, 12),
            (5.2, 5.2, 9.1, 9.1), (14.9, 14.9, 18.8, 18.8), (5.2, 18.8, 9.1, 14.9), (14.9, 9.1, 18.8, 5.2),
        };
        foreach (var (x1, y1, x2, y2) in lines)
            g.Children.Add(new LineGeometry(new Point(x1 * s, y1 * s), new Point(x2 * s, y2 * s)));
        g.Freeze();
        return g;
    }

    /// Codex hexagon-in-hexagon.
    private static Geometry CodexGeometry(double size)
    {
        double s = size / 24.0;
        var g = Geometry.Parse(
            "M 12,3 L 19.4,7.3 L 19.4,16.7 L 12,21 L 4.6,16.7 L 4.6,7.3 Z " +
            "M 12,8.4 L 15.1,10.2 L 15.1,13.8 L 12,15.6 L 8.9,13.8 L 8.9,10.2 Z").Clone();
        g.Transform = new ScaleTransform(s, s);
        g.Freeze();
        return g;
    }

    // MARK: Real provider logos (template-tinted, like the macOS app)
    //
    // The bundled PNGs are used as stencils: their alpha channel masks a solid
    // rectangle of the requested color — the WPF equivalent of NSImage's
    // template rendering, so the logos follow the theme's foreground color.

    private static readonly Dictionary<string, ImageBrush?> LogoCache = new();

    private static ImageBrush? LogoMask(string id)
    {
        if (LogoCache.TryGetValue(id, out var cached)) return cached;
        ImageBrush? brush = null;
        var file = id switch
        {
            "claude" => "claude.png",
            "codex" => "openai.png",
            "cursor" => "cursor.png",
            _ => null,
        };
        if (file != null)
        {
            try
            {
                var img = new BitmapImage(new Uri($"pack://application:,,,/Resources/Images/{file}"));
                brush = new ImageBrush(img) { Stretch = Stretch.Uniform };
                brush.Freeze();
            }
            catch { }
        }
        LogoCache[id] = brush;
        return brush;
    }

    public static FrameworkElement For(string id, double size, Color color)
    {
        // The placeholder "no CLI found" ring gets a plain question mark.
        if (id == Settings.PlaceholderId)
        {
            return new Grid
            {
                Width = size,
                Height = size,
                Children =
                {
                    new TextBlock
                    {
                        Text = "?",
                        FontSize = size * 0.85,
                        FontWeight = FontWeights.Bold,
                        Foreground = new SolidColorBrush(color),
                        HorizontalAlignment = HorizontalAlignment.Center,
                        VerticalAlignment = VerticalAlignment.Center,
                    },
                },
            };
        }

        if (LogoMask(id) is ImageBrush mask)
        {
            return new Rectangle
            {
                Width = size,
                Height = size,
                Fill = new SolidColorBrush(color),
                OpacityMask = mask,
            };
        }
        var brush = new SolidColorBrush(color);
        Path path = id switch
        {
            "claude" => new Path
            {
                Data = ClaudeGeometry(size),
                Stroke = brush,
                StrokeThickness = size * 0.1,
                StrokeStartLineCap = PenLineCap.Round,
                StrokeEndLineCap = PenLineCap.Round,
            },
            "codex" => new Path
            {
                Data = CodexGeometry(size),
                Stroke = brush,
                StrokeThickness = size * 0.08,
                StrokeStartLineCap = PenLineCap.Round,
                StrokeEndLineCap = PenLineCap.Round,
                StrokeLineJoin = PenLineJoin.Round,
            },
            _ => new Path
            {
                Data = ClaudeGeometry(size),
                Stroke = brush,
                StrokeThickness = size * 0.1,
            },
        };
        path.Width = size;
        path.Height = size;
        return path;
    }
}
