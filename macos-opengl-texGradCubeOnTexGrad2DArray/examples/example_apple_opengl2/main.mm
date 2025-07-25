#import <Cocoa/Cocoa.h>
#import <OpenGL/gl3.h>
#import <OpenGL/glu.h>

//-----------------------------------------------------------------------------------
// AppView
//-----------------------------------------------------------------------------------
constexpr int num = 100;
constexpr int fbSize = 8;

@interface AppView : NSOpenGLView
{
    NSTimer*    animationTimer;
    float time;
    GLuint cubeSampleProgram;
    GLuint showProgram;
    GLuint tex;
    GLuint framebuffer;
    GLuint posLoc;
    GLuint tex1;
}
@end

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
    GLenum err = glGetError();
    if (err) {
      NSLog(@"Err Compiling: %x", err);
      exit(1);
    }
    return shader;
}

GLint createProgram(const char* vsrc, const char* fsrc) {
  GLint vs = compileShader(GL_VERTEX_SHADER, vsrc);
  GLint fs = compileShader(GL_FRAGMENT_SHADER, fsrc);
  GLint program = glCreateProgram();
  glAttachShader(program, vs);
  glAttachShader(program, fs);
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
  return program;
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

void checkError(const char* msg)
{
  GLenum err = glGetError();
  if (err) {
      NSLog(@"Err Initializing: %x, %s", err, msg);
  }
}

int max(int a, int b) {
  return a > b ? a : b;
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

  const char vs[] = R"(\
    #version 410
    layout(location = 0) in vec4 position;
    void main() {
        gl_Position = position;
    }
  )";

  const char cubeFS[] = R"(\
    #version 410
    out vec4 fragColor;
    uniform samplerCube tex;
    void main() {
       vec2 uv = gl_FragCoord.xy / vec2(8, 8);
       fragColor = texture(tex, vec3(uv * 2.0 - 1.0, 1));
    }
  )";

  const char showFS[] = R"(\
    #version 410
    out vec4 fragColor;
    uniform sampler2D tex;
    void main() {
       vec2 uv = gl_FragCoord.xy / vec2(1280, 720);
       fragColor = texture(tex, uv);
    }
  )";

  cubeSampleProgram = createProgram(vs, cubeFS);
  showProgram = createProgram(vs, showFS);

  posLoc = glGetAttribLocation(cubeSampleProgram, "position");
  GLuint va;
  glGenVertexArrays(1, &va);
  glBindVertexArray(va);

  GLuint buf;
  glGenBuffers(1, &buf);
  static const float quad[] = {
      -1, -2,
       1, -2,
      -1,  2,
      -1,  2,
       1, -2,
       1,  2,
  };
  glBindBuffer(GL_ARRAY_BUFFER, buf);
  glBufferData(GL_ARRAY_BUFFER, sizeof(quad), quad, GL_STATIC_DRAW);
  glEnableVertexAttribArray(posLoc);
  glVertexAttribPointer(posLoc, 2, GL_FLOAT, GL_FALSE, 0, nullptr);
  checkError("make va");

  glGenTextures(1, &tex);
  glBindTexture(GL_TEXTURE_CUBE_MAP, tex);
  int width = 8;
  int height = 8;
  uint8_t colors[][4] = {
    { 0xFF, 0x00, 0x00, 0xFF },
    { 0xFF, 0xFF, 0x00, 0xFF },
    { 0x00, 0xFF, 0x00, 0xFF },
    { 0x00, 0xFF, 0xFF, 0xFF },
    { 0x00, 0x00, 0xFF, 0xFF },
    { 0xFF, 0x00, 0xFF, 0xFF },
  };
  uint8_t color[width * height * 4];
  for (int mipLevel = 0; mipLevel < 4; ++mipLevel) {
    int mipWidth = max(1, width >> mipLevel);
    int mipHeight = max(1, height >> mipLevel);
    for (int face = 0; face < 6; ++face) {
      uint8_t *c = colors[face];
      for (int y = 0; y < mipHeight; ++y) {
        for (int x = 0; x < mipWidth; ++x) {
          int offset = (y * mipWidth + x) * 4;
          color[offset + 0] = c[0] >> mipLevel;
          color[offset + 1] = c[1] >> mipLevel;
          color[offset + 2] = c[2] >> mipLevel;
          color[offset + 3] = c[3];
        }
      }
      glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X + face, mipLevel, GL_RGBA, mipWidth, mipHeight, 0, GL_RGBA, GL_UNSIGNED_BYTE, &color);
    }
  }
  glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MIN_FILTER, GL_NEAREST_MIPMAP_NEAREST);
  glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  checkError("make texture");

  GLuint fbTex;
  glGenTextures(1, &fbTex);
  glBindTexture(GL_TEXTURE_2D, fbTex);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, fbSize, fbSize, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

  glGenFramebuffers(1, &framebuffer);
  glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, fbTex, 0);
  checkError("fb");

  glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

-(void)updateAndDrawDemoView
{
  time += 0.016;

  [[self openGLContext] makeCurrentContext];

  glViewport(0, 0, fbSize, fbSize);
  glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
  glUseProgram(cubeSampleProgram);
  glDrawArrays(GL_TRIANGLES, 0, 6);
  glBindFramebuffer(GL_FRAMEBUFFER, 0);

  float scale = self.window.screen.backingScaleFactor;

  GLsizei width  = (float)self.frame.size.width * scale;
  GLsizei height = (float)self.bounds.size.height * scale;

  glViewport(0, 0, width, height); // no idea why width and height are wrong. Suspect dpr but no docs beacuse Apple
  float c = fmod(time, 1.0f);
  glClearColor(c, c, c, 1.0f);
  glClear(GL_COLOR_BUFFER_BIT);

  glUseProgram(showProgram);
  glDrawArrays(GL_TRIANGLES, 0, 6);
  checkError("draw");

  // Present
  [[self openGLContext] flushBuffer];

  if (!animationTimer)
      animationTimer = [NSTimer scheduledTimerWithTimeInterval:0.017 target:self selector:@selector(animationTimerFired:) userInfo:nil repeats:YES];
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
