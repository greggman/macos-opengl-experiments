#import <Cocoa/Cocoa.h>
#import <OpenGL/gl3.h>
#import <OpenGL/glu.h>

#import <sstream>
#import <vector>

//-----------------------------------------------------------------------------------
// AppView
//-----------------------------------------------------------------------------------
constexpr int num = 100;

@interface AppView : NSOpenGLView
{
    NSTimer*    animationTimer;
    float time;
    GLuint texProgram;
    GLuint fillProgram;
    GLuint tex;
}
@end

void checkError(const char *msg) {
  GLenum err = glGetError();
  if (err) {
      NSLog(@"Err %s: %x", msg, err);
      exit(1);
  }
}

GLint compileShader(GLenum type, const char* src)
{
    auto shader = glCreateShader(type);
    //NSLog(@"src: %s", src);
    glShaderSource(shader, 1, &src, nullptr);
    glCompileShader(shader);
    GLint success = 0;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &success);
    if (!success) {
        GLint len;
        glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &len);
        GLchar *log = (GLchar*)malloc(len);
        glGetShaderInfoLog(shader, len, nullptr, log);
        NSLog(@"Failed to compile!: %s", log);
    }
    checkError("compiling");
    return shader;
}

void linkProgram(GLuint program) {
  glLinkProgram(program);
  GLint success = 0;
  glGetProgramiv(program, GL_LINK_STATUS, &success);
  if (!success) {
      GLint len;
      glGetProgramiv(program, GL_INFO_LOG_LENGTH, &len);
      GLchar *log = (GLchar*)malloc(len);
      glGetProgramInfoLog(program, len, &len, log);
      NSLog(@"Failed to link!: %s", log);
      exit(1);
  }
}

@implementation AppView

-(void)prepareOpenGL
{
    [super prepareOpenGL];

#ifndef DEBUG
    GLint swapInterval = 1;
    [[self openGLContext] setValues:&swapInterval forParameter:NSOpenGLCPSwapInterval];
    if (swapInterval == 0)
        NSLog(@"Error: Cannot set swap interval.");
#endif
}

-(void)initialize
{
  [[self openGLContext] makeCurrentContext];
  NSLog(@"version : %s", glGetString(GL_VERSION));
  NSLog(@"vendor  : %s", glGetString(GL_VENDOR));
  NSLog(@"renderer: %s", glGetString(GL_RENDERER));
  NSLog(@"GLSL ver: %s", glGetString(GL_SHADING_LANGUAGE_VERSION));
  glEnable(GL_PROGRAM_POINT_SIZE);
  //glPointSize(10);

  GLint maxVertexAttribs = 0;
  glGetIntegerv(GL_MAX_VERTEX_ATTRIBS, &maxVertexAttribs);
  NSLog(@"MAX_VERTEX_ATTRIBS: %d", maxVertexAttribs);

  checkError("getString");

  texProgram = glCreateProgram();
  {
    GLuint vs = compileShader(GL_VERTEX_SHADER,
    R"(#version 410
    
    layout(location = 0) in vec2 p;
    
    void main() {
      gl_Position = vec4(p, 0, 1);
    }
    )");

    GLuint fs = compileShader(GL_FRAGMENT_SHADER,
    R"(#version 410
     precision highp float;
    
     uniform sampler2DShadow u_tex;
     out vec4 outColor;
    
     void main() {
       outColor = textureGather(u_tex, vec2(0.5), 0.5);
     }
    )");

    glAttachShader(texProgram, vs);
    glAttachShader(texProgram, fs);

    linkProgram(texProgram);
  }

  checkError("programs");

  glGenTextures(1, &tex);
  glBindTexture(GL_TEXTURE_2D, tex);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT16, 2, 2, 0, GL_DEPTH_COMPONENT, GL_UNSIGNED_SHORT, nullptr);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_COMPARE_MODE, GL_COMPARE_REF_TO_TEXTURE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_COMPARE_FUNC, GL_LESS);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_SWIZZLE_R, GL_ONE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_SWIZZLE_G, GL_ONE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_SWIZZLE_B, GL_ONE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_SWIZZLE_A, GL_ONE);
  checkError("texture1");

  GLuint tex2;
  glGenTextures(1, &tex2);
  glBindTexture(GL_TEXTURE_2D, tex2);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 2, 2, 0, GL_RGBA, GL_UNSIGNED_SHORT, nullptr);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  checkError("texture2");

  GLuint fb;
  glGenFramebuffers(1, &fb);
  glBindFramebuffer(GL_FRAMEBUFFER, fb);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex2, 0);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, tex, 0);
  {
    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    NSLog(@"status: %d == %d", status, GL_FRAMEBUFFER_COMPLETE);
    if (status != GL_FRAMEBUFFER_COMPLETE) {
      exit(1);
    }
  }
  glEnable(GL_SCISSOR_TEST);
  for (int i = 0; i < 4; ++i) {
    int x = i % 2;
    int y = i / 2;
    glViewport(x, y, 1, 1);
    glScissor(x, y, 1, 1);
    glClearDepth(i * 0.2 + 0.2);
    glClear(GL_DEPTH_BUFFER_BIT);
  }
  glDisable(GL_SCISSOR_TEST);
  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  checkError("fill");

  GLuint va;
  glGenVertexArrays(1, &va);
  glBindVertexArray(va);

  GLuint buf;
  glGenBuffers(1, &buf);
  static const float quad[] = {
      -1, -1,
       1, -1,
      -1,  1,
      -1,  1,
       1, -1,
       1,  1,
  };
  glBindBuffer(GL_ARRAY_BUFFER, buf);
  glBufferData(GL_ARRAY_BUFFER, sizeof(quad), quad, GL_STATIC_DRAW);
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, nullptr);
  checkError("va");
}

-(void)updateAndDrawDemoView
{
  time += 0.016;

  [[self openGLContext] makeCurrentContext];
  //GLsizei width  = (float)self.bounds.size.width;
  //GLsizei height = (float)self.bounds.size.height;
  //glViewport(0, 0, width, height);

  GLuint tex3;
  glGenTextures(1, &tex3);
  glBindTexture(GL_TEXTURE_2D, tex3);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 1, 1, 0, GL_RGBA, GL_UNSIGNED_SHORT, nullptr);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  checkError("texture3");

  GLuint fb;
  glGenFramebuffers(1, &fb);
  glBindFramebuffer(GL_FRAMEBUFFER, fb);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex3, 0);
  {
    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    NSLog(@"status: %d == %d", status, GL_FRAMEBUFFER_COMPLETE);
    if (status != GL_FRAMEBUFFER_COMPLETE) {
      exit(1);
    }
  }
  glViewport(0, 0, 1, 1);
  glClearColor(0.3, 0.3, 0.3, 1.0f);
  glClear(GL_COLOR_BUFFER_BIT);

  checkError("clear");

  glUseProgram(texProgram);
  glBindTexture(GL_TEXTURE_2D, tex);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_SWIZZLE_R, GL_ONE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_SWIZZLE_G, GL_ONE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_SWIZZLE_B, GL_ONE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_SWIZZLE_A, GL_ONE);

  glDrawArrays(GL_TRIANGLES, 0, 6);

  // Present
  [[self openGLContext] flushBuffer];

  std::vector<uint8_t> pixel(4);
  glReadPixels(0, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, &pixel[0]);
  checkError("read");

  NSLog(@"pixel : %d %d %d %d", pixel[0], pixel[1], pixel[2], pixel[3]);
  NSLog(@"pixel : %f %f %f %f", float(pixel[0]) / 255.0f, float(pixel[1]) / 255.0f, float(pixel[2]) / 255.0f, float(pixel[3]) / 255.0f);

  exit(0);
}

-(void)reshape                              { [super reshape]; [[self openGLContext] update]; [self updateAndDrawDemoView]; }
-(void)drawRect:(NSRect)bounds              { [self updateAndDrawDemoView]; }
-(void)animationTimerFired:(NSTimer*)timer  { [self setNeedsDisplay:YES]; }
-(void)dealloc                              { animationTimer = nil; }

@end

//-----------------------------------------------------------------------------------
// AppDelegate
//-----------------------------------------------------------------------------------

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, readonly) NSWindow* window;
@end

@implementation AppDelegate
@synthesize window = _window;

-(BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication
{
    return YES;
}

-(NSWindow*)window
{
    if (_window != nil)
        return (_window);

    NSRect viewRect = NSMakeRect(100.0, 100.0, 100.0 + 1280.0, 100 + 720.0);

    _window = [[NSWindow alloc] initWithContentRect:viewRect styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:YES];
    [_window setTitle:@"OpenGL Example"];
    [_window setAcceptsMouseMovedEvents:YES];
    [_window setOpaque:YES];
    [_window makeKeyAndOrderFront:NSApp];

    return (_window);
}

-(void)setupMenu
{
    NSMenu* mainMenuBar = [[NSMenu alloc] init];
    NSMenu* appMenu;
    NSMenuItem* menuItem;

    appMenu = [[NSMenu alloc] initWithTitle:@"OpenGL Example"];
    menuItem = [appMenu addItemWithTitle:@"OpenGL Example" action:@selector(terminate:) keyEquivalent:@"q"];
    [menuItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand];

    menuItem = [[NSMenuItem alloc] init];
    [menuItem setSubmenu:appMenu];

    [mainMenuBar addItem:menuItem];

    appMenu = nil;
    [NSApp setMainMenu:mainMenuBar];
}

-(void)dealloc
{
    _window = nil;
}

-(void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Make the application a foreground application (else it won't receive keyboard events)
    ProcessSerialNumber psn = {0, kCurrentProcess};
    TransformProcessType(&psn, kProcessTransformToForegroundApplication);

    // Menu
    [self setupMenu];

    NSOpenGLPixelFormatAttribute attrs[] =
    {
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFADepthSize, 32,
        NSOpenGLPFAOpenGLProfile, NSOpenGLProfileVersion3_2Core,
        0
    };

    NSOpenGLPixelFormat* format = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];
    AppView* view = [[AppView alloc] initWithFrame:self.window.frame pixelFormat:format];
    format = nil;
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 1070
    if (floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_6)
        [view setWantsBestResolutionOpenGLSurface:YES];
#endif // MAC_OS_X_VERSION_MAX_ALLOWED >= 1070
    [self.window setContentView:view];

    if ([view openGLContext] == nil)
        NSLog(@"No OpenGL Context!");

    [view initialize];
}

@end

//-----------------------------------------------------------------------------------
// Application main() function
//-----------------------------------------------------------------------------------

int main(int argc, const char* argv[])
{
    @autoreleasepool
    {
        NSApp = [NSApplication sharedApplication];
        AppDelegate* delegate = [[AppDelegate alloc] init];
        [[NSApplication sharedApplication] setDelegate:delegate];
        [NSApp run];
    }
    return NSApplicationMain(argc, argv);
}
