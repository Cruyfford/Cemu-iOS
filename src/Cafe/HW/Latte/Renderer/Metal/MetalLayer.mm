#include "Cafe/HW/Latte/Renderer/Metal/MetalLayer.h"

#if defined(CEMU_IOS)
#import <QuartzCore/CAMetalLayer.h>
#import <UIKit/UIKit.h>

// On iOS the frontend owns the view. The window handle passed by the frontend is
// the CAMetalLayer that backs the emulation view (or a UIView backed by one).
void* CreateMetalLayer(void* handle, float& scaleX, float& scaleY)
{
	id obj = (__bridge id)handle;
	CAMetalLayer* layer = nil;
	if ([obj isKindOfClass:[CAMetalLayer class]])
		layer = (CAMetalLayer*)obj;
	else if ([obj isKindOfClass:[UIView class]] && [((UIView*)obj).layer isKindOfClass:[CAMetalLayer class]])
		layer = (CAMetalLayer*)((UIView*)obj).layer;

	if (!layer)
	{
		scaleX = scaleY = 1.0f;
		return nullptr;
	}

	scaleX = scaleY = (float)layer.contentsScale;
	// MetalLayerHandle releases the layer when it is destroyed
	return (void*)CFBridgingRetain(layer);
}
#else
#include "Cafe/HW/Latte/Renderer/MetalView.h"

void* CreateMetalLayer(void* handle, float& scaleX, float& scaleY)
{
	NSView* view = (NSView*)handle;

	MetalView* childView = [[MetalView alloc] initWithFrame:view.bounds];
	childView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	childView.wantsLayer = YES;

	[view addSubview:childView];

	const NSRect points = [childView frame];
    const NSRect pixels = [childView convertRectToBacking:points];

	scaleX = (float)(pixels.size.width / points.size.width);
    scaleY = (float)(pixels.size.height / points.size.height);

	return childView.layer;
}
#endif
